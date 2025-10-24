//
//  WithDependenciesMacro.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/29.
//


import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin

public struct WithDependenciesMacro: MemberMacro {
        
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // 1. 获取宏的参数列表，例如 `(\.dandanClient, \.userClient)`
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return []
        }
        
        // 2. 遍历每一个参数（每一个 KeyPath）
        return arguments.compactMap { element in
            // `element.expression` 就是 KeyPath 表达式本身，例如 `\.dandanClient`
            guard let keyPath = element.expression.as(KeyPathExprSyntax.self) else {
                return nil
            }
            
            // 3. 从 KeyPath 中提取变量名
            //    对于 `\.dandanClient`，我们要提取出 "dandanClient"
            //    我们找到 KeyPath 的最后一个组件，并获取它的名字
            guard let variableName = keyPath.components.last?.component.as(KeyPathPropertyComponentSyntax.self)?.declName.baseName else {
                return nil
            }
            
            // 4. 构建并返回要生成的代码
            //    例如，生成 "@Dependency(\.dandanClient) var dandanClient"
            return """
            @Dependency(\(keyPath)) var \(variableName)
            """
        }
    }
}

@main
struct DependenciesMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WithDependenciesMacro.self,
    ]
}
