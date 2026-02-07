import Foundation

actor NotesService {

    enum NotesError: LocalizedError {
        case scriptFailed(String)
        case permissionDenied
        case parseError(String)
        case timeout

        var errorDescription: String? {
            switch self {
            case .scriptFailed(let msg):
                return "AppleScript実行エラー: \(msg)"
            case .permissionDenied:
                return "メモアプリへのアクセスが拒否されました。システム設定 > プライバシーとセキュリティ > オートメーション で許可してください。"
            case .parseError(let msg):
                return "データ解析エラー: \(msg)"
            case .timeout:
                return "メモアプリからの応答がタイムアウトしました。"
            }
        }
    }

    // Track running osascript processes so we can kill them on app quit
    private var runningProcesses: [Process] = []

    /// Kill all running osascript processes. Call on app termination.
    func terminateAll() {
        for process in runningProcesses where process.isRunning {
            process.terminate()
        }
        runningProcesses.removeAll()
    }

    // MARK: - Incremental Metadata Fetch (folder-by-folder, instant UI)

    /// Fetch notes metadata incrementally, folder by folder.
    /// Each folder's notes are delivered via callback so the UI updates immediately.
    /// - onFolders: called once with all folder names
    /// - onFolderLoaded: called per folder with (notes, completedCount, totalFolders)
    func fetchNotesMetadataIncremental(
        onFolders: @escaping @Sendable ([String]) -> Void,
        onFolderLoaded: @escaping @Sendable ([NoteItem], Int, Int) -> Void
    ) async throws {
        // Step 1: Get folder names (single Apple Event — instant)
        let folderScript = """
        tell application "Notes"
            with timeout of 30 seconds
                set fNames to name of every folder
                set AppleScript's text item delimiters to linefeed
                return fNames as text
            end timeout
        end tell
        """
        let folderResult = try runAppleScript(folderScript, timeout: 45)
        let folderNames = folderResult.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        onFolders(folderNames)

        let totalFolders = folderNames.count
        var completedFolders = 0

        // Step 2: For each folder, bulk-fetch note IDs + names (2 Apple Events per folder)
        // Each folder typically has ~200 notes, so `as text` is O(200²) — fast.
        for folderName in folderNames {
            try Task.checkCancellation()

            let escaped = escapeForAppleScript(folderName)
            let script = """
            tell application "Notes"
                with timeout of 60 seconds
                    tell folder "\(escaped)"
                        set nIds to id of every note
                        set nNames to name of every note
                        set AppleScript's text item delimiters to linefeed
                        return (nIds as text) & "<<SEC>>" & (nNames as text)
                    end tell
                end timeout
            end tell
            """

            completedFolders += 1

            let output: String
            do {
                output = try runAppleScript(script, timeout: 90)
            } catch {
                onFolderLoaded([], completedFolders, totalFolders)
                continue
            }

            let sections = output.components(separatedBy: "<<SEC>>")
            guard sections.count >= 2 else {
                onFolderLoaded([], completedFolders, totalFolders)
                continue
            }

            let ids = sections[0].components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let names = sections[1].components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            var folderNotes: [NoteItem] = []
            for (i, id) in ids.enumerated() {
                let title = i < names.count ? names[i] : ""
                folderNotes.append(NoteItem(
                    id: id,
                    title: title,
                    htmlBody: "",
                    plainText: "",
                    folder: folderName,
                    createdAt: .distantPast,
                    modifiedAt: .distantPast
                ))
            }

            onFolderLoaded(folderNotes, completedFolders, totalFolders)
        }
    }

    // MARK: - Stream all notes for direct export (no list display needed)

    /// Export result containing counts and skipped note info.
    struct ExportResult: Sendable {
        let written: Int
        let total: Int
        let errors: [String]
    }

    /// Export all notes folder by folder using JXA (JavaScript for Automation).
    /// Errors on individual folders/notes are logged and skipped instead of stopping.
    func exportAllNotes(
        writer: @Sendable ([NoteItem]) throws -> Int,
        onProgress: @escaping @Sendable (Int, Int) -> Void,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws -> ExportResult {
        var errors: [String] = []

        // Step 1: Get total note count + folder count + ALL note IDs (JXA)
        let initScript = """
        (() => {
            const Notes = Application('Notes')
            const allIds = Notes.notes.id()
            const folderCount = Notes.folders.length
            return JSON.stringify({ids: allIds, fc: folderCount})
        })()
        """
        let initResult = try runJXA(initScript, timeout: 120)
        guard let initData = initResult.data(using: .utf8),
              let initParsed = try? JSONSerialization.jsonObject(with: initData) as? [String: Any],
              let allNoteIds = initParsed["ids"] as? [String],
              let folderCount = initParsed["fc"] as? Int
        else { return ExportResult(written: 0, total: 0, errors: ["初期化に失敗しました"]) }

        let totalCount = allNoteIds.count
        let allNoteIdSet = Set(allNoteIds)
        var exportedIds = Set<String>()

        onProgress(0, totalCount)

        var totalWritten = 0
        var processedCount = 0

        // Step 2: For each folder BY INDEX — ensures every folder is processed,
        // even when multiple accounts have folders with the same name.
        for folderIndex in 0..<folderCount {
            try Task.checkCancellation()

            let jxaScript = """
            (() => {
                const Notes = Application('Notes')
                const folder = Notes.folders[\(folderIndex)]
                let folderName = 'folder_\(folderIndex)'
                try { folderName = folder.name() } catch(e) {}
                let ids
                try { ids = folder.notes.id() } catch(e) {
                    return JSON.stringify({f: folderName, n: [], e: 'ID取得失敗'})
                }
                if (ids.length === 0) return JSON.stringify({f: folderName, n: []})
                let names
                try { names = folder.notes.name() } catch(e) { names = ids.map(()=>'') }
                // Fast path: bulk body/plaintext
                try {
                    const bodies = folder.notes.body()
                    const plains = folder.notes.plaintext()
                    const notes = ids.map((id, i) => [id, names[i]||'', bodies[i]||'', plains[i]||''])
                    return JSON.stringify({f: folderName, n: notes})
                } catch(e) {}
                // Slow path: per-note body
                const notes = []
                for (let i = 0; i < ids.length; i++) {
                    let body = '', plain = ''
                    try { body = folder.notes[i].body() || '' } catch(e) {}
                    try { plain = folder.notes[i].plaintext() || '' } catch(e) {}
                    notes.push([ids[i], names[i]||'', body, plain])
                }
                try {
                    return JSON.stringify({f: folderName, n: notes})
                } catch(e) {
                    // JSON too large — return metadata only
                    const meta = ids.map((id, i) => [id, names[i]||'', '', ''])
                    return JSON.stringify({f: folderName, n: meta, e: 'body_truncated'})
                }
            })()
            """

            onStatus("フォルダ (\(folderIndex + 1)/\(folderCount))")

            var output: String
            do {
                output = try runJXA(jxaScript, timeout: 600)
            } catch {
                // JXA failed entirely — try metadata-only fetch
                let metaScript = """
                (() => {
                    const Notes = Application('Notes')
                    const folder = Notes.folders[\(folderIndex)]
                    let name = 'folder_\(folderIndex)'
                    try { name = folder.name() } catch(e) {}
                    let ids = [], names = []
                    try { ids = folder.notes.id() } catch(e) {
                        return JSON.stringify({f: name, n: [], e: 'ID取得失敗'})
                    }
                    try { names = folder.notes.name() } catch(e) {}
                    const meta = ids.map((id, i) => [id, names[i]||'', '', ''])
                    return JSON.stringify({f: name, n: meta, e: 'meta_only'})
                })()
                """
                do {
                    output = try runJXA(metaScript, timeout: 120)
                } catch {
                    errors.append("フォルダ[\(folderIndex)]: JXA実行エラー - \(error.localizedDescription)")
                    continue
                }
            }

            guard !output.isEmpty,
                  let jsonData = output.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let folderName = parsed["f"] as? String,
                  let rows = parsed["n"] as? [[String]]
            else {
                errors.append("フォルダ[\(folderIndex)]: JSON解析エラー")
                continue
            }

            let jxaError = parsed["e"] as? String ?? ""
            if !jxaError.isEmpty && jxaError != "body_truncated" && jxaError != "meta_only" {
                errors.append("フォルダ[\(folderIndex)] \(folderName): \(jxaError)")
            }

            onStatus("フォルダ (\(folderIndex + 1)/\(folderCount)) \(folderName)")

            var folderNotes: [NoteItem] = []
            let needsBodyFetch = jxaError == "body_truncated" || jxaError == "meta_only"

            if needsBodyFetch && !rows.isEmpty {
                // Bodies not available — batch-fetch them separately
                let bodyBatchSize = 20
                for bodyStart in stride(from: 0, to: rows.count, by: bodyBatchSize) {
                    try Task.checkCancellation()
                    let bodyEnd = min(bodyStart + bodyBatchSize, rows.count)
                    let bodyScript = """
                    (() => {
                        const Notes = Application('Notes')
                        const folder = Notes.folders[\(folderIndex)]
                        const r = []
                        for (let i = \(bodyStart); i < \(bodyEnd); i++) {
                            let b = '', p = ''
                            try { b = folder.notes[i].body() || '' } catch(e) {}
                            try { p = folder.notes[i].plaintext() || '' } catch(e) {}
                            r.push([b, p])
                        }
                        return JSON.stringify(r)
                    })()
                    """
                    var bodies: [[String]] = []
                    if let bOut = try? runJXA(bodyScript, timeout: 300),
                       let bData = bOut.data(using: .utf8),
                       let bArr = try? JSONSerialization.jsonObject(with: bData) as? [[String]] {
                        bodies = bArr
                    }
                    for j in bodyStart..<bodyEnd {
                        guard j < rows.count, rows[j].count >= 2 else { continue }
                        let bi = j - bodyStart
                        let body = bi < bodies.count ? (bodies[bi].first ?? "") : ""
                        let plain = bi < bodies.count && bodies[bi].count > 1 ? bodies[bi][1] : ""
                        exportedIds.insert(rows[j][0])
                        folderNotes.append(NoteItem(
                            id: rows[j][0], title: rows[j][1],
                            htmlBody: body, plainText: plain,
                            folder: folderName,
                            createdAt: Date(), modifiedAt: Date()
                        ))
                    }
                    onStatus("フォルダ \(folderName) 本文取得中 (\(bodyEnd)/\(rows.count))")
                }
            } else {
                for row in rows where row.count >= 4 {
                    exportedIds.insert(row[0])
                    folderNotes.append(NoteItem(
                        id: row[0], title: row[1],
                        htmlBody: row[2], plainText: row[3],
                        folder: folderName,
                        createdAt: Date(), modifiedAt: Date()
                    ))
                }
            }

            if !folderNotes.isEmpty {
                do {
                    let count = try writer(folderNotes)
                    totalWritten += count
                } catch {
                    errors.append("フォルダ「\(folderName)」: 書き込みエラー - \(error.localizedDescription)")
                }
                processedCount += folderNotes.count
                onProgress(processedCount, totalCount)
            }
        }

        // Step 3: Reconciliation — find notes NOT in any folder.
        // These are typically in "Recently Deleted" or notes from folders that
        // failed even per-note fallback. Use batched index access with per-note
        // try/catch for body/plaintext (handles corrupted/large notes gracefully).
        let missingIds = allNoteIdSet.subtracting(exportedIds)
        if !missingIds.isEmpty {
            onStatus("未分類メモを取得中... (\(missingIds.count)件)")

            // Build index map: noteId → index in Notes.notes[]
            var indexMap: [String: Int] = [:]
            for (index, id) in allNoteIds.enumerated() {
                indexMap[id] = index
            }

            let missingIndices = missingIds.compactMap { indexMap[$0] }.sorted()
            let unmappedIds = missingIds.filter { indexMap[$0] == nil }
            for id in unmappedIds {
                errors.append("メモID \(id): インデックス不明（スキップ）")
            }

            // Batched index access with retry: batch of 10, retry individually on failure.
            let batchSize = 10
            for batchStart in stride(from: 0, to: missingIndices.count, by: batchSize) {
                try Task.checkCancellation()

                let batchEnd = min(batchStart + batchSize, missingIndices.count)
                let batchIndices = Array(missingIndices[batchStart..<batchEnd])
                let indicesJson = batchIndices.map { String($0) }.joined(separator: ",")

                let jxaScript = """
                (() => {
                    const Notes = Application('Notes')
                    const indices = [\(indicesJson)]
                    const result = []
                    const errIndices = []
                    for (const idx of indices) {
                        try {
                            const n = Notes.notes[idx]
                            const id = n.id()
                            const name = n.name() || ''
                            let body = ''
                            let plain = ''
                            try { body = n.body() || '' } catch(e) {}
                            try { plain = n.plaintext() || '' } catch(e) {}
                            let folder = ''
                            try { folder = n.container().name() } catch(e) {}
                            result.push([id, name, body, plain, folder])
                        } catch(e) {
                            errIndices.push(idx)
                        }
                    }
                    return JSON.stringify({n: result, e: errIndices})
                })()
                """

                onStatus("未分類メモ (\(batchStart + 1)-\(batchEnd)/\(missingIndices.count))")

                var batchNotes: [NoteItem] = []
                var failedIndices: [Int] = []

                if let batchOutput = try? runJXA(jxaScript, timeout: 300),
                   let jsonData = batchOutput.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let rows = parsed["n"] as? [[String]] {
                    // Batch succeeded
                    for row in rows where row.count >= 5 {
                        let folder = row[4].isEmpty ? "最近削除した項目" : row[4]
                        batchNotes.append(NoteItem(
                            id: row[0], title: row[1],
                            htmlBody: row[2], plainText: row[3],
                            folder: folder,
                            createdAt: Date(), modifiedAt: Date()
                        ))
                    }
                    if let errIdx = parsed["e"] as? [Int] {
                        failedIndices = errIdx
                    }
                } else {
                    // Batch failed entirely — retry all individually
                    failedIndices = batchIndices
                }

                // Retry failed indices one by one
                for idx in failedIndices {
                    let single = fetchSingleNoteByIndex(idx)
                    if let note = single.note {
                        batchNotes.append(note)
                    }
                    if let err = single.error {
                        errors.append(err)
                    }
                }

                if !batchNotes.isEmpty {
                    do {
                        let count = try writer(batchNotes)
                        totalWritten += count
                    } catch {
                        errors.append("未分類メモ[\(batchStart+1)-\(batchEnd)]: 書き込みエラー")
                    }
                }

                processedCount += batchIndices.count
                onProgress(processedCount, totalCount)
            }
        }

        return ExportResult(written: totalWritten, total: totalCount, errors: errors)
    }

    /// Fetch a single note by its global index in Notes.notes[].
    /// Returns the note and/or an error message.
    private func fetchSingleNoteByIndex(_ idx: Int) -> (note: NoteItem?, error: String?) {
        let jxaScript = """
        (() => {
            const Notes = Application('Notes')
            try {
                const n = Notes.notes[\(idx)]
                const id = n.id()
                const name = n.name() || ''
                let body = '', plain = '', folder = ''
                try { body = n.body() || '' } catch(e) {}
                try { plain = n.plaintext() || '' } catch(e) {}
                try { folder = n.container().name() } catch(e) {}
                return JSON.stringify([id, name, body, plain, folder])
            } catch(e) {
                return JSON.stringify({e: e.message || String(e)})
            }
        })()
        """

        guard let output = try? runJXA(jxaScript, timeout: 60),
              let data = output.data(using: .utf8) else {
            return (nil, "メモ[index=\(idx)]: 取得失敗")
        }

        if let errorObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errMsg = errorObj["e"] as? String {
            return (nil, "メモ[index=\(idx)]: \(errMsg)")
        }

        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [String],
              arr.count >= 5 else {
            return (nil, "メモ[index=\(idx)]: 解析エラー")
        }

        let folder = arr[4].isEmpty ? "最近削除した項目" : arr[4]
        return (NoteItem(
            id: arr[0], title: arr[1],
            htmlBody: arr[2], plainText: arr[3],
            folder: folder,
            createdAt: Date(), modifiedAt: Date()
        ), nil)
    }

    // MARK: - Fetch bodies for export (batch by folder)

    func fetchBodiesForExport(
        selectedIds: Set<String>,
        folderNames: [String],
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [NoteItem] {
        let total = selectedIds.count
        var result: [NoteItem] = []
        var fetched = 0

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")

        func parseDate(_ str: String) -> Date {
            let s = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return dateFormatter.date(from: s)
                ?? fallbackFormatter.date(from: s)
                ?? Date()
        }

        for folderName in folderNames {
            // Check cancellation between folders
            try Task.checkCancellation()

            let escaped = escapeForAppleScript(folderName)
            let script = """
            tell application "Notes"
                with timeout of 300 seconds
                    tell folder "\(escaped)"
                        set nIds to id of every note
                        set nNames to name of every note
                        set nBodies to body of every note
                        set nPlains to plaintext of every note
                        set nCreated to creation date of every note
                        set nModified to modification date of every note
                        set noteCount to count of nIds
                        set output to {}
                        repeat with i from 1 to noteCount
                            set end of output to (item i of nIds) & "<<F>>" & (item i of nNames) & "<<F>>" & (item i of nBodies) & "<<F>>" & (item i of nPlains) & "<<F>>" & ((item i of nCreated) as «class isot» as string) & "<<F>>" & ((item i of nModified) as «class isot» as string)
                        end repeat
                        set AppleScript's text item delimiters to "<<R>>"
                        return output as text
                    end tell
                end timeout
            end tell
            """

            let output: String
            do {
                output = try runAppleScript(script, timeout: 360)
            } catch {
                continue
            }

            guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            for line in output.components(separatedBy: "<<R>>") {
                let fields = line.components(separatedBy: "<<F>>")
                guard fields.count >= 6 else { continue }

                let noteId = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard selectedIds.contains(noteId) else { continue }

                result.append(NoteItem(
                    id: noteId,
                    title: fields[1].trimmingCharacters(in: .whitespacesAndNewlines),
                    htmlBody: fields[2],
                    plainText: fields[3],
                    folder: folderName,
                    createdAt: parseDate(fields[4]),
                    modifiedAt: parseDate(fields[5])
                ))

                fetched += 1
                onProgress(fetched, total)
            }
        }

        let foundIds = Set(result.map(\.id))
        let missingIds = selectedIds.subtracting(foundIds)
        for noteId in missingIds {
            try Task.checkCancellation()

            let escaped = escapeForAppleScript(noteId)
            let script = """
            tell application "Notes"
                with timeout of 30 seconds
                    try
                        set n to first note whose id is "\(escaped)"
                        set nTitle to name of n
                        set nBody to body of n
                        set nPlain to plaintext of n
                        set nCreated to (creation date of n) as «class isot» as string
                        set nModified to (modification date of n) as «class isot» as string
                        set nFolder to ""
                        try
                            set nFolder to name of container of n
                        end try
                        return nTitle & "<<F>>" & nBody & "<<F>>" & nPlain & "<<F>>" & nCreated & "<<F>>" & nModified & "<<F>>" & nFolder
                    end try
                end timeout
            end tell
            """
            if let output = try? runAppleScript(script, timeout: 45) {
                let fields = output.components(separatedBy: "<<F>>")
                guard fields.count >= 6 else { continue }
                result.append(NoteItem(
                    id: noteId,
                    title: fields[0].trimmingCharacters(in: .whitespacesAndNewlines),
                    htmlBody: fields[1],
                    plainText: fields[2],
                    folder: fields[5].trimmingCharacters(in: .whitespacesAndNewlines),
                    createdAt: parseDate(fields[3]),
                    modifiedAt: parseDate(fields[4])
                ))
            }
            fetched += 1
            onProgress(fetched, total)
        }

        return result
    }

    // MARK: - Single note detail (for preview)

    func fetchNoteDetail(noteId: String) async throws -> NoteItem {
        let escaped = escapeForAppleScript(noteId)
        let script = """
        tell application "Notes"
            with timeout of 30 seconds
                set n to first note whose id is "\(escaped)"
                set nTitle to name of n
                set nBody to body of n
                set nPlain to plaintext of n
                set nCreated to (creation date of n) as «class isot» as string
                set nModified to (modification date of n) as «class isot» as string
                set nFolder to ""
                try
                    set nFolder to name of container of n
                end try
                return nTitle & "<<F>>" & nBody & "<<F>>" & nPlain & "<<F>>" & nCreated & "<<F>>" & nModified & "<<F>>" & nFolder
            end timeout
        end tell
        """
        let output = try runAppleScript(script, timeout: 45)
        let fields = output.components(separatedBy: "<<F>>")
        guard fields.count >= 6 else {
            throw NotesError.parseError("メモの詳細を取得できませんでした")
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")

        func parseDate(_ str: String) -> Date {
            let s = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return dateFormatter.date(from: s)
                ?? fallbackFormatter.date(from: s)
                ?? Date()
        }

        return NoteItem(
            id: noteId,
            title: fields[0].trimmingCharacters(in: .whitespacesAndNewlines),
            htmlBody: fields[1],
            plainText: fields[2],
            folder: fields[5].trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: parseDate(fields[3]),
            modifiedAt: parseDate(fields[4])
        )
    }

    // MARK: - Create note (for import)

    func createNote(title: String, body: String, folderName: String) async throws {
        let escapedTitle = escapeForAppleScript(title)
        let escapedBody = escapeForAppleScript(body)
        let escapedFolder = escapeForAppleScript(folderName)

        let script = """
        tell application "Notes"
            with timeout of 30 seconds
                set targetFolder to missing value
                repeat with f in folders
                    if name of f is "\(escapedFolder)" then
                        set targetFolder to f
                        exit repeat
                    end if
                end repeat
                if targetFolder is missing value then
                    make new folder with properties {name:"\(escapedFolder)"}
                    set targetFolder to folder "\(escapedFolder)"
                end if
                tell targetFolder
                    make new note with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
                end tell
            end timeout
        end tell
        """
        _ = try runAppleScript(script, timeout: 45)
    }

    // MARK: - Private

    private func runAppleScript(_ script: String, timeout: TimeInterval = 120) throws -> String {
        return try runOsascript(["-e", script], timeout: timeout)
    }

    private func runJXA(_ script: String, timeout: TimeInterval = 120) throws -> String {
        return try runOsascript(["-l", "JavaScript", "-e", script], timeout: timeout)
    }

    /// Run osascript with process tracking, concurrent pipe reading, and Swift-level timeout.
    private func runOsascript(_ arguments: [String], timeout: TimeInterval) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        runningProcesses.append(process)

        let timer: DispatchSourceTimer?
        if timeout > 0 {
            let t = DispatchSource.makeTimerSource(queue: .global())
            t.schedule(deadline: .now() + timeout)
            t.setEventHandler { [weak process] in
                guard let p = process, p.isRunning else { return }
                p.terminate()
            }
            t.resume()
            timer = t
        } else {
            timer = nil
        }

        defer {
            timer?.cancel()
            runningProcesses.removeAll { $0 === process }
        }

        try process.run()

        // Read pipes CONCURRENTLY to avoid deadlock when output exceeds pipe buffer (~64KB)
        var outputData = Data()
        var errorData = Data()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        process.waitUntilExit()
        group.wait()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus == 15 || process.terminationReason == .uncaughtSignal {
            throw NotesError.timeout
        }

        if process.terminationStatus != 0 {
            if errorOutput.contains("not allowed") || errorOutput.contains("permission") || errorOutput.contains("-1743") {
                throw NotesError.permissionDenied
            }
            throw NotesError.scriptFailed(errorOutput)
        }

        return output.trimmingCharacters(in: .newlines)
    }

    private func escapeForAppleScript(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\", with: "\\\\")
                  .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func escapeForJavaScript(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\", with: "\\\\")
                  .replacingOccurrences(of: "\"", with: "\\\"")
                  .replacingOccurrences(of: "\n", with: "\\n")
                  .replacingOccurrences(of: "\r", with: "\\r")
    }
}
