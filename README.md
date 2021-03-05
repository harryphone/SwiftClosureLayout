# Swift中闭包底层原理探索

# 闭包的定义

我们先看下`Swift`官方文档的定义：

『闭包』是独立的代码块, 可以在你代码中随意传递和使用 。Swift 中的闭包与 Objective-C/C 中的 Block、其他编程语言中的匿名函数相似。

闭包可以从定义它们的代码的上下文中捕获和存储任何变量。这也被称为这些变量和常量被暂时关闭使用。并且 Swift 负责处理你所捕获的内存进行管理。

我们看到，闭包和匿名函数相似，而且闭包多了一个功能，可以在代码的上下文中捕获和存储任何变量，我们从探索闭包的捕获功能来探索底层。

# 闭包的捕获

先看两段简单的代码：
```swift
var age = 18
let printAge = {
    print(age)
}
age += 1
printAge() //19
```

这里很明显，闭包捕获了`age`变量，即使`age`变量变化了，闭包依然能打出正确的值。

```swift
var age = 18
let printAge = {
    [age] in
    print(age)
}
age += 1
printAge() //18
```

这段代码多了`[age] in`，其余一样，这个称之为闭包捕获列表（`closure capture list`）。那为什么多了闭包捕获列表后，`age`值打印出来没有变？

这两段代码看起来，前面代码的闭包捕获的是`age`的引用，而后面代码捕获的是`age`的值拷贝，我们一起深入底层探索下

# 闭包捕获列表（`closure capture list`）

我们先探索简单的闭包捕获列表（`closure capture list`），我们先简化下代码：
```swift
var age = 18
let printAge = {
    [age] in
    let temp = age
}
```

然后查看[`SIL`文件](https://juejin.cn/post/6904994620628074510)：
![](https://p6-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/3a400d245565403ea7ca1b086251d884~tplv-k3u1fbpfcp-watermark.image)

我们看到，闭包在`main`函数里被定义成了`@closure #1`，我们去找`@closure #1`的实现：

```swift
// closure #1 in 
sil private @closure #1 () -> () in main : $@convention(thin) (Int) -> () {
// %0 "age"                                       // users: %2, %1
bb0(%0 : $Int):
  debug_value %0 : $Int, let, name "age", argno 1 // id: %1
  debug_value %0 : $Int, let, name "temp"         // id: %2
  %3 = tuple ()                                   // user: %4
  return %3 : $()                                 // id: %4
} // end sil function 'closure #1 () -> () in main'
```

我们看到了一件神奇的事情，闭包类型从`() -> ()`变成了`(Int) -> ()`，`age`貌似从第一个参数位置传进来了。我们可以弄的复杂一点验证下：
```swift
var age = 18
var name = "Tom"
let printAge = {
    [age, name] (weight: Double) in
    var temp = age
    let tempName = name
}
```

在[`SIL`文件](https://juejin.cn/post/6904994620628074510)中展示：
```swift
// closure #1 in 
sil private @closure #1 (Swift.Double) -> () in main : $@convention(thin) (Double, Int, @guaranteed String) -> () {
// %0 "weight"                                    // user: %3
// %1 "age"                                       // users: %7, %4
// %2 "name"                                      // users: %8, %5
bb0(%0 : $Double, %1 : $Int, %2 : $String):
  debug_value %0 : $Double, let, name "weight", argno 1 // id: %3
  debug_value %1 : $Int, let, name "age", argno 2 // id: %4
  debug_value %2 : $String, let, name "name", argno 3 // id: %5
  %6 = alloc_stack $Int, var, name "temp"         // users: %7, %9
  store %1 to %6 : $*Int                          // id: %7
  debug_value %2 : $String, let, name "tempName"  // id: %8
  dealloc_stack %6 : $*Int                        // id: %9
  %10 = tuple ()                                  // user: %11
  return %10 : $()                                // id: %11
} // end sil function 'closure #1 (Swift.Double) -> () in main'
```

这次，我在捕获列表里放了2个值，并且闭包本身也带了一个`weight`的参数。我们看到，`sil文件`实现的时候，把闭包从`(Double) -> ()`变成了`(Double, Int, String) -> ()`。这样，保存在捕获列表里的值，就如同函数参数传进来一样，进行了拷贝。

总结一下闭包捕获列表（`closure capture list`）原理：增加闭包本身的参数个数，添加参数的类型与放在闭包捕获列表中的值的类型一致，并放在原闭包参数列表的后面，最后把捕获列表中的值通过参数的形式传给函数内部，传值的拷贝形式的和函数参数传值一致。

在引用类型作为闭包捕获列表中的值时，我们时常看到`[weak self]`、`[unowned self]`用来解决循环引用的问题，在`sil文件`中，他们改写成参数的时候前面会添加标记，所以在函数体里会做弱引用或者无主引用的操作，这里就不带着一起看了。

有一点，一般在循环引用中，`self`持有着闭包，而闭包又持有着`self`，他们俩的生命周期大多数情况是一致的，所以在解除循环引用中，用`[unowned self]`会更好一点，原因：
* 用`[weak self]`后，`self`会变成可选属性，在`self`调用属性或者方法时，要加一个`?`，看上去没有那么美观。而`[unowned self]`在self调用属性或者方法时，并不需要加`?`。
* 效率问题，`[weak self]`会添加`self`的弱引用计数，而弱引用计数需要开辟一个新的空间存`SideTable`，`SideTable`中会存放弱引用计数及其它引用计数，详情看[Swift的引用计数原理](https://juejin.cn/post/6906438952895709197)。而开辟空间操作相对于常规操作来说，性能消耗的比较多。

# 从`SIL文件`分析闭包捕获上下文

我们拿官网中例子探索下：
```swift
func makeIncrementer() -> () -> Int {
    var runningTotal = 12
    func incrementer() -> Int {
        runningTotal += 1
        return runningTotal
    }
    return incrementer
}
```

生成`SIL文件`：
```swift
// makeIncrementer()
sil hidden @main.makeIncrementer() -> () -> Swift.Int : $@convention(thin) () -> @owned @callee_guaranteed () -> Int {
bb0:
// 在堆上分配一个引用计数@box包装"runningTotal"
  %0 = alloc_box ${ var Int }, var, name "runningTotal" // users: %8, %7, %6, %1
  %1 = project_box %0 : ${ var Int }, 0           // user: %4
  // 初始化12字面量
  %2 = integer_literal $Builtin.Int64, 12         // user: %3
  %3 = struct $Int (%2 : $Builtin.Int64)          // user: %4
  store %3 to %1 : $*Int                          // id: %4
  // function_ref incrementer #1 () in makeIncrementer()
  // 声明闭包@incrementer #1 ()
  %5 = function_ref @incrementer #1 () -> Swift.Int in main.makeIncrementer() -> () -> Swift.Int : $@convention(thin) (@guaranteed { var Int }) -> Int // user: %7
  strong_retain %0 : ${ var Int }                 // id: %6
  // 把包装过后的"runningTotal"传给闭包
  %7 = partial_apply [callee_guaranteed] %5(%0) : $@convention(thin) (@guaranteed { var Int }) -> Int // user: %9
  strong_release %0 : ${ var Int }                // id: %8
  // 返回闭包
  return %7 : $@callee_guaranteed () -> Int       // id: %9
} // end sil function 'main.makeIncrementer() -> () -> Swift.Int'

// incrementer #1 () in makeIncrementer()
sil private @incrementer #1 () -> Swift.Int in main.makeIncrementer() -> () -> Swift.Int : $@convention(thin) (@guaranteed { var Int }) -> Int {
// %0 "runningTotal"                              // user: %1
bb0(%0 : ${ var Int }):
// 给%1传进来的经过box包装的"runningTotal"
  %1 = project_box %0 : ${ var Int }, 0           // users: %16, %4, %2
  debug_value_addr %1 : $*Int, var, name "runningTotal", argno 1 // id: %2
  // 要加的字面量1
  %3 = integer_literal $Builtin.Int64, 1          // user: %8
  %4 = begin_access [modify] [dynamic] %1 : $*Int // users: %13, %5, %15
  %5 = struct_element_addr %4 : $*Int, #Int._value // user: %6
  // 取出"runningTotal"
  %6 = load %5 : $*Builtin.Int64                  // user: %8
  %7 = integer_literal $Builtin.Int1, -1          // user: %8
  // 调用加法，给"runningTotal"加一
  %8 = builtin "sadd_with_overflow_Int64"(%6 : $Builtin.Int64, %3 : $Builtin.Int64, %7 : $Builtin.Int1) : $(Builtin.Int64, Builtin.Int1) // users: %10, %9
  %9 = tuple_extract %8 : $(Builtin.Int64, Builtin.Int1), 0 // user: %12
  %10 = tuple_extract %8 : $(Builtin.Int64, Builtin.Int1), 1 // user: %11
  // 判断是否溢出
  cond_fail %10 : $Builtin.Int1, "arithmetic overflow" // id: %11
  // 把算好的值再次赋给box包装的"runningTotal"
  %12 = struct $Int (%9 : $Builtin.Int64)         // user: %13
  store %12 to %4 : $*Int                         // id: %13
  %14 = tuple ()
  end_access %4 : $*Int                           // id: %15
  %16 = begin_access [read] [dynamic] %1 : $*Int  // users: %17, %18
  // 打开盒子取值
  %17 = load %16 : $*Int                          // user: %19
  end_access %16 : $*Int                          // id: %18
  // 把值返回出去
  return %17 : $Int                               // id: %19
} // end sil function 'incrementer #1 () -> Swift.Int in main.makeIncrementer() -> () -> Swift.Int'

```

我们从代码里可以看到，变量`runningTotal`并没有直接放在栈上，而是开辟了空间，放在了堆上，这样就把值类型变成了引用类型的存在。

而闭包的类型也从`() -> Int`类型变成了`(@guaranteed { var Int }) -> Int`，引用类型的`runningTotal`正好从参数处传了进来，这样实现了闭包捕获值变量的过程。

这样我们大概知道了闭包捕获值的原理，但是闭包本质上是一个匿名函数，底层就是个指向代码块实现的指针，那么是如何保存捕获的值的呢？我们在`SIL文件`中看不出来，所以我们得往更底层探索闭包的实现。

# 生成`LLVM文件`

比`SIL文件`更底层的只有中间表示`LLVM`以及汇编指令了，两者都可以探索闭包的实现，但越底层越不符合人的理解，所以这边挑选了`LLVM`，`LLVM`的语法可以看我前面写的[文章](https://juejin.cn/post/6935341725091102751)，不难哦。

我们先写下最简单的代码：
```swift
struct Test {
    var biBao: (() -> ())
}
```

我们定义一个结构体，里面就放一个闭包，看下在`LLVM`中是如何显示的
```llvm
%swift.type = type { i64 }
%swift.refcounted = type { %swift.type*, i64 }
%T4main4TestV = type <{ %swift.function }>
%swift.function = type { i8*, %swift.refcounted* }
```

我们看到，结构体`Test`中闭包的类型就是`%swift.function`

`%swift.function`结构体存放了`i8*`和`%swift.refcounted*`，`i8*`是一个指针，我们可以看成`void *`，`%swift.refcounted*`是`%swift.refcounted`类型的指针

`%swift.refcounted`结构体存放了`%swift.type*`和`i64`，`i64`是64位的整形，`%swift.type*`是`%swift.type`类型的指针

`%swift.type`是64位的整形。

如果看过我[Metadata](https://juejin.cn/post/6919034854159941645)文章介绍的，应该能很快意识到，`%swift.refcounted`是一个`HeapObject`，而`%swift.type`就是`Metadata`，我们搜源码也可以证实这一点。

我们可以搜`swift.type`、`swift.function`等关键字，看下在`IR`中的定义：
```c++
FunctionPairTy = createStructType(*this, "swift.function", {
    FunctionPtrTy,
    RefCountedPtrTy,
});

RefCountedStructTy =
    llvm::StructType::create(getLLVMContext(), "swift.refcounted");
RefCountedPtrTy = RefCountedStructTy->getPointerTo(/*addrspace*/ 0);

TypeMetadataStructTy = createStructType(*this, "swift.type", {
    MetadataKindTy          // MetadataKind Kind;
 });
```

`RefCountedPtrTy`看着并不明显，但是从`TypeMetadataStructTy`推断出`RefCountedPtrTy`就是`HeapObject`。

那可以总结下，闭包的底层是`FunctionPairTy`类型，用`Swift`代码表达大概是这个样子：
```swift
struct HeapObject {
    var Kind: UInt64
    var refcount: UInt64
}

struct FunctionPairTy {
    // 闭包代码实现的函数地址
    var FunctionPtrTy: UnsafeMutableRawPointer
    // 在堆空间保存的捕获上下文变量的指针，如果没有捕获，为null
    var RefCountedPtrTy: UnsafeMutablePointer<HeapObject>
}
```

# 从`LLVM文件`分析闭包捕获值的流程

我们还是用同样的demo：
```swift
func makeIncrementer() -> (() -> Int) {
    var runningTotal = 12
    func incrementer() -> Int {
        runningTotal += 1
        return runningTotal
    }
    return incrementer
}
```
生成`LLVM文件`：
```llvm
define hidden swiftcc { i8*, %swift.refcounted* } @"main.makeIncrementer() -> () -> Swift.Int"() #0 {
entry:
  %runningTotal.debug = alloca %TSi*, align 8
  %0 = bitcast %TSi** %runningTotal.debug to i8*
  call void @llvm.memset.p0i8.i64(i8* align 8 %0, i8 0, i64 8, i1 false)
  %1 = call noalias %swift.refcounted* @swift_allocObject(%swift.type* getelementptr inbounds (%swift.full_boxmetadata, %swift.full_boxmetadata* @metadata, i32 0, i32 2), i64 24, i64 7) #1
  %2 = bitcast %swift.refcounted* %1 to <{ %swift.refcounted, [8 x i8] }>*
  %3 = getelementptr inbounds <{ %swift.refcounted, [8 x i8] }>, <{ %swift.refcounted, [8 x i8] }>* %2, i32 0, i32 1
  %4 = bitcast [8 x i8]* %3 to %TSi*
  store %TSi* %4, %TSi** %runningTotal.debug, align 8
  %._value = getelementptr inbounds %TSi, %TSi* %4, i32 0, i32 0
  store i64 12, i64* %._value, align 8
  %5 = call %swift.refcounted* @swift_retain(%swift.refcounted* returned %1) #1
  call void @swift_release(%swift.refcounted* %1) #1
  %6 = insertvalue { i8*, %swift.refcounted* } { i8* bitcast (i64 (%swift.refcounted*)* @"partial apply forwarder for incrementer #1 () -> Swift.Int in main.makeIncrementer() -> () -> Swift.Int" to i8*), %swift.refcounted* undef }, %swift.refcounted* %1, 1
  ret { i8*, %swift.refcounted* } %6
}
```

我们找寻下被捕获的值`12`，我们很快能发现一句：
```llvm
store i64 12, i64* %._value, align 8
```
值`12`被存到了`%._value`，`%._value`是什么呢：
```llvm
%._value = getelementptr inbounds %TSi, %TSi* %4, i32 0, i32 0
```
`getelementptr`获取元素指针，`%TSi`指的是`i64`，所以很明显`%._value`取的是结构体`%4`中第一个元素的指针，`%4`又是从哪里来的呢？
```llvm
%4 = bitcast [8 x i8]* %3 to %TSi*
```
`%4`就是`%3`，这里强转了一下类型。看下`%3`如何得到：
```llvm
%3 = getelementptr inbounds <{ %swift.refcounted, [8 x i8] }>, <{ %swift.refcounted, [8 x i8] }>* %2, i32 0, i32 1
```
`%3`取的结构体`{ %swift.refcounted, [8 x i8] }`类型`%2`的第二个元素，也就是说，`%3`是结构体`{ %swift.refcounted, [8 x i8] }`中`[8 x i8]`的指针，上面的值`12`放到了该位置。我们在分析下剩下的；

```llvm
%0 = bitcast %TSi** %runningTotal.debug to i8*
  call void @llvm.memset.p0i8.i64(i8* align 8 %0, i8 0, i64 8, i1 false)
  %1 = call noalias %swift.refcounted* @swift_allocObject(%swift.type* getelementptr inbounds (%swift.full_boxmetadata, %swift.full_boxmetadata* @metadata, i32 0, i32 2), i64 24, i64 7) #1
  %2 = bitcast %swift.refcounted* %1 to <{ %swift.refcounted, [8 x i8] }>*
  ...
  %5 = call %swift.refcounted* @swift_retain(%swift.refcounted* returned %1) #1
  call void @swift_release(%swift.refcounted* %1) #1
  %6 = insertvalue { i8*, %swift.refcounted* } { i8* bitcast (i64 (%swift.refcounted*)* @"partial apply forwarder for incrementer #1 () -> Swift.Int in main.makeIncrementer() -> () -> Swift.Int" to i8*), %swift.refcounted* undef }, %swift.refcounted* %1, 1
  ret { i8*, %swift.refcounted* } %6
```
`%1`调用了`swift_allocObject`向堆申请了空间，类型是`%swift.refcounted*`的指针类型，`%2`把`%1`的指针类型强转了，变成了上面分析的`<{ %swift.refcounted, [8 x i8] }>*`，这里你可以理解成父类与子类的关系。

`%5`是引用计数的调用，这里对我们帮助不大，忽略这个。

最后的`%6`被函数`retrun`了出去，看结构和我们分析的闭包底层结构一致。结构体中，`i8*`被插入了`{ i8* bitcast (i64 (%swift.refcounted*)* @"partial apply forwarder for incrementer #1 () -> Swift.Int in main.makeIncrementer() -> () -> Swift.Int" to i8*), %swift.refcounted* undef }`，也就是闭包代码的实现地址，`%swift.refcounted*`被插入了`%1`的地址，也就是放入值`12`的`{ %swift.refcounted, [8 x i8] }`类型的指针。

所以我们把刚才`Swift`表达的代码更完善一点
```swift
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
```
和原来相比，多了一个`Box`类型，这个类型就是用引用类型的结构来包裹被捕获的值，这个`value`不一定是`Int`，你可以写成一个范型

我打印了下内存地址，成功在堆空间找到值`12`，顺便验证下第一个地址是不是函数实现的指针。

![](https://p6-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/2faf4df2b9fd44ce8b7d2888a0c74f95~tplv-k3u1fbpfcp-watermark.image)


# 多个捕获值分析

我们把上面的demo改造下：
```swift
func makeIncrementer() -> () -> Int {
    var runningTotal = 12
    var temp1 = 1
    let temp2 = 2
    var temp3 = "a"
    let temp4 = "b"
    func incrementer() -> Int {
        runningTotal += 1
        temp1 += temp2
        temp3 += temp4
        return runningTotal
    }
    return incrementer
}
```

我们直接在`LLVM文件`中看下前面`Box`类型中`value`中存放了什么：
![](https://p9-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/f703792f699e4193aae141edec398940~tplv-k3u1fbpfcp-watermark.image)

我们看到，这里并没有直接存放了一个`Int`值，而是连续放了一堆值，我们简单翻译下，`%swift.refcounted*`可以看成`Box*`，`%TSi`是`Int`类型，`%TSS`是`String`类型，所以这里的`value`放了`[Box*, Box*, Int, Box*, String]`

我们在内存中验证下：
![](https://p9-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/3636a6342f714d39b3ce0e48cac69a87~tplv-k3u1fbpfcp-watermark.image)

这里和底层分析的类型相匹配，但这里有个奇怪的点，为什么有些值被`Box`包装了一下，而有些值没有。仔细对比下源码，不难发现，如果被捕获的值在闭包内有改动，那么该值就被`Box`包装，反之就不会。

被捕获的值是否被包装，在`sil文件`中也能看出来：
![](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/9d9d2cf955cf4d02a168436387f18ddc~tplv-k3u1fbpfcp-watermark.image)
闭包在底层实现被隐式转换的时候，看参数是否带`{}`,如果带上了`{}`的话，就是被`Box`包装过的。

# 总结

一个闭包底层由16个字节组成，前8个字节存放的是函数代码实现地址的指针，一般指向代码段，后8个字节存放指向捕获值地址的指针，一般指向堆区，可以画一张图表示下：
![](https://p6-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/37005f71de664b24a6d88c4530fa5721~tplv-k3u1fbpfcp-watermark.image)

捕获值存放在`Value`的位置，但这里需要分一下情况：
* 如果没有捕获值，`BoxPtr`直接为`nil`，就不存在`Value`了，打印`BoxPtr`的地址都是0，这里就不展示了。函数就是一种没有捕获值的闭包，感兴趣的小伙伴可以自己试一下。
* 如果只有1个捕获值，那么直接把值存放在`Value`的位置，不管这个捕获值在闭包内是否变动过
* 如果有多个捕获值，那么会把值依次挨着放在`Value`的位置，但是如果这个捕获值在闭包内变动过，那么这个值会经过`Box`再次包装，然后把包装后的引用地址放在`Value`的对应的位置，可以在画一张图明显点：
![](https://p9-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/d2b1ca18a5f0403a8d1b99198c4968da~tplv-k3u1fbpfcp-watermark.image)


总觉得捕获值这块的逻辑有源码，但是翻找整整两天没有找到，可能本人能力还不够，希望有大佬帮一把，或者告知下确实没有源码。

最后附上查看闭包内存的代码，[GitHub地址](https://github.com/harryphone/SwiftClosureLayout)，希望能帮到一部分同学。


