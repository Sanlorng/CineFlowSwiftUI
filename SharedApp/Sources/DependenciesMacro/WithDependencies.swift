//
//  WithDependencies.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/29.
//


import ComposableArchitecture

@attached(member, names: arbitrary) // 我们不再预先知道成员的名字，所以移除 names 参数
public macro WithDependencies(
    _ dependencies: PartialKeyPath<DependencyValues> ...
) = #externalMacro(
    module: "DependenciesMacroImpl",
    type: "WithDependenciesMacro" // 我们将创建一个新的实现类型
)
