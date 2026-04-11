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
        let tool = try context.tool(named: "SecretGenerator")
        let inputFiles = FileManager.default.fileExists(atPath: inputFile.path()) ? [inputFile] : []

        return [
            .buildCommand(
                displayName: "Generating Secrets.swift from \(inputFile.lastPathComponent)",
                executable: tool.url,
                arguments: [inputFile.path(), outputFilePath.path()],
                inputFiles: inputFiles,
                outputFiles: [outputFilePath]
            )
        ]
    }
}
