//
//  main.swift
//  SwiftClosureLayout
//
//  Created by HarryPhone on 2021/3/3.
//

import Foundation



struct FunctionPairTy {
    var FunctionPtrTy: UnsafeMutableRawPointer
    var RefCountedPtrTy: UnsafeMutablePointer<Box>
}

struct HeapObject {
    var Kind: UInt64
    var refcount: UInt64
}

struct Box {
    var refCounted: HeapObject
    var value: Int
}

class Student {
    var age = 3
}

//func makeIncrementer() -> () -> Int {
//    var runningTotal = 12
//    var temp1 = 1
//    let temp2 = 2
//    var temp3 = "dada"
//    let temp4 = "hehe"
//    var temp5 = CGPoint.init(x: 3, y: 4)
//    let temp6 = CGPoint.init(x: 5, y: 6)
//    var st = Student()
//    func incrementer() -> Int {
//        runningTotal += 1
//        temp1 += temp2
//        temp3 += temp4
//        temp5.x += temp6.x
//        st = Student()
//        return 100
//    }
//    return incrementer
//}

func makeIncrementer() -> () -> Int {
//    var runningTotal = 12
    func incrementer() -> Int {
//        runningTotal += 1
        return 100
    }
    return incrementer
}

// 这里需要用结构体把闭包包一层，不然会被底层自己逻辑包装了。。
struct FuncShell {
    var fun: () -> Int
}

func testFunc() -> Int {
    return 10
}

var fun = FuncShell.init(fun: makeIncrementer())

var closure = withUnsafeMutablePointer(to: &fun) {
    return UnsafeMutableRawPointer($0).assumingMemoryBound(to: FunctionPairTy.self).pointee
}

//var ptr = unsafeBitCast(fun, to: FunctionPairTy.self)

print(closure)



print("end")




