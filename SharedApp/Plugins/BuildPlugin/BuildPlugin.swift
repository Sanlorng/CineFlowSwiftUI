//
//  BuildPlugin.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/27.
//

import Foundation
import PackagePlugin

@main
struct BuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [PackagePlugin.Command] {
        let inputFile = context.package.directoryURL.appending(path: "secrets.env")
        let outputFilePath = context.pluginWorkDirectoryURL.appending(path: "Secrets.swift")
        let scriptPath = context.package.directoryURL.appending(path: "Plugins/BuildPlugin/generate-secrets.sh")
        let inputFiles = FileManager.default.fileExists(atPath: inputFile.path()) ? [inputFile] : []

        return [
            .buildCommand(
                displayName: "Generating Secrets.swift from \(inputFile.lastPathComponent)",
                executable: .init(fileURLWithPath: "/bin/bash"),
                arguments: [scriptPath.path(), inputFile.path(), outputFilePath.path()],
                inputFiles: inputFiles,
                outputFiles: [outputFilePath]
            )
        ]
    }
}
