//
//  BuildPlugin.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/27.
//
import PackagePlugin
import Foundation

@main
struct BuildPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [PackagePlugin.Command] {
        // 更新输入文件的名称
        let inputFile = context.package.directoryURL.appending(path: "secrets.env")
        
        let outputFilePath = context.pluginWorkDirectoryURL.appending(path: "Secrets.swift")
        let tool = try context.tool(named: "SecretGenerator")
        
        return [
            .buildCommand(
                displayName: "Generating Secrets.swift from \(inputFile.lastPathComponent)",
                executable: tool.url,
                arguments: [inputFile.path(), outputFilePath.path()],
                inputFiles: [
                    inputFile // 依赖于新的 secrets.env 文件
                ],
                outputFiles: [
                    outputFilePath
                ]
            )
        ]
    }
    
    
}
