#import "ctufit-thesis.typ": *
#let cpp = box[C#h(-0.1em)++\u{2060}]

= Higher order functions and just-in-time compilation

This chapter introduces higher-order functions in TNL and explores Python binding strategies for them. It also discusses the use of just-in-time compilation techniques to improve the performance of Python callbacks that would allow them to reach the native performance of the original #cpp code.

== Higher-order functions in TNL

// https://tnl-project.gitlab.io/tnl/classTNL_1_1Containers_1_1Array.html#aab46e9d7161d32fd887683f2d2c52046
TNL utilizes higher-order functions and methods quite extensively to allow users to express their custom logic. The TNL arrays have the `.forElements` and `.forAllElements` methods that allow running any custom element-wise operations on the elements. These methods take a lambda function that takes an index and a reference to the current element. The lambda is then called for each element of the array or each element inside given bounds. This is performed at the same place where the array is allocated. That is, it allow parallel execution of the GPU provided the lambda is declared `__cuda_callable__`.

#code1([Example of `.forElements` TNL Array method as showcased in the documentation], <tnl_array_forelements_code_example>, 
```cpp
   const int size = 10;
   Containers::Array< float, Device > a( size );
   Containers::Array< float, Device > b( size );
   b = 0;
 
   // Initiate the elements of array `a`
   a.forAllElements(
      [] __cuda_callable__( int i, float& value )
      {
         value = i;
      } );
 
   // Initiate elements of array `b` with indexes 0-4 using `a_view`
   auto a_view = a.getView();
   b.forElements( 0,
                  5,
                  [ = ] __cuda_callable__( int i, float& value )
                  {
                     value = a_view[ i ] + 4.0;
                  } );
```
)

Another example could be the `parallelFor` function from the Algorithms namespace. As the name suggests, it handles execution of generic loops in a parallel way. Accepting an index range and a lambda function with further optional arguments. Interestingly, it even supports 2D and 3D multi-index. Allowing users to, for example, easily setup the data as shown in the code snippet below.

#code1([Example of `parallelFor` function as showcased in the documentation], <tnl_array_parallelfor_code_example>, 
```cpp
   const int xSize = 10;
   const int ySize = 10;
   const int zSize = 10;
   const int size = xSize * ySize * zSize;
   Vector< double, Devices::Cuda > v( size );

   auto view = v.getView();
   auto init = [ = ] __cuda_callable__( const StaticArray< 3, int >& i ) mutable
   {
      view[ ( i.z() * ySize + i.y() ) * xSize + i.x() ] = c;
   };
   StaticArray< 3, int > begin{ 0, 0, 0 };
   StaticArray< 3, int > end{ xSize, ySize, zSize };
   parallelFor< Device >( begin, end, init );
```
)

The `parallelFor` gets a lot of use and flexibility thanks to context capturing ability of #cpp lambda functions. Lambda functions, especially those introduced with #cpp 11 standard, are not merely anonymous pieces of code. When a lambda refers to variables from the surrounding scope, the compiler generates a small callable object, often called a closure, that stores the captured data together with the function body. The data may be captured by value, meaning a copy is stored inside the closure, or by reference, meaning the closure keeps access to an existing object. In practice, this means that the lambda can behave as a compact custom function that already carries its own local state.

This is particularly useful for higher-order interfaces such as `parallelFor`. The algorithm itself only needs to know how to iterate over a range of indices and when to invoke the callback. Any additional information, such as views of arrays, scalar parameters, material constants, or auxiliary buffers, can be supplied through the lambda capture instead of being threaded through the algorithm interface explicitly. The resulting API remains generic and reusable, while the user code remains local, readable, and close to the point where the data are prepared.

If such a callable needs to be passed through a more uniform interface, it can also be wrapped in `std::function`, which provides a common type for storing and forwarding arbitrary callable objects with a compatible signature. In that case, even a capturing lambda with its otherwise unnamed compiler-generated type can be treated as an ordinary callback value. Together, lambda capture and callable wrappers give #cpp libraries a practical way to express higher-order operations where user-defined behavior is combined with state prepared in the surrounding code.

== TNL Functions

== PyTNL and Nanobind

== Numba <numba_introduction>

== NVRTC <nvrtc_introduction>

== Benchmark <function_calling_from_cpp_benchmark>

#figure(
  table(
    columns: (1fr, auto, auto, auto, auto),
    align: (left, left, left, right, right),
    inset: (x: 8pt, y: 10pt),
    table.header([*Method*], [*Binding*], [*Callback*], [*Avg \ (ms/iter)*], [*vs baseline*]),
    [Python list], [—], [—], [82.589], [(baseline)],
    [Python `DoubleVector`], [—], [—], [237.579], [2.9× slower],
    [NumPy `*= 2.0`], [—], [—], [0.757], [109.1× faster],
    [C++ `multiplyAll`], [—], [—], [1.222], [67.6× faster],
    [`mapAll`], [`nb::object`], [Python λ], [167.431], [2.0× slower],
    [`mapAll`], [`nb::callable`], [Python λ], [169.207], [2.0× slower],
    [`mapAll`], [`nb::callable`], [`@jit`], [379.349], [4.6× slower],
    [`mapAll`], [`std::function`], [`@jit`], [402.222], [4.9× slower],
    [`forAll`], [fn ptr], [`@cfunc`], [10.584], [7.8× faster],
    [`seqFor`], [fn ptr], [`@cfunc`], [5.356], [15.4× faster],
    table.hline(stroke: 1.5pt),
  ),
  caption: [
    Scenario A --- element-wise multiply (`vec[i] *= 2.0`), $N = 2^(21) = 2 thin 097 thin 152$
    sorted by calling strategy. Baseline is plain Python list iteration.
    Benchmark ran on a PC with Ryzen 3600 CPU in WSL2 environment.
  ],
) <benchmark_scenario_a_table>

#figure(
  table(
    columns: (1fr, auto, auto, auto, auto),
    align: (left, left, left, right, right),
    inset: (x: 8pt, y: 10pt),
    table.header([*Method*], [*Binding*], [*Callback*], [*Avg \ (ms/iter)*], [*vs baseline*]),
    [Python list], [—], [Python fn], [475.667], [(baseline)],
    [Python list], [—], [`@jit` fn], [346.476], [1.4× faster],
    [Python `DoubleVector`], [—], [—], [743.670], [1.6× slower],
    [NumPy vectorized], [—], [—], [59.106], [8.0× faster],
    [C++ `heavyComputeAll`], [—], [—], [34.620], [13.7× faster],
    [`mapAll`], [`nb::object`], [Python fn], [567.003], [1.2× slower],
    [`mapAll`], [`nb::callable`], [Python fn], [566.121], [1.2× slower],
    [`mapAll`], [`nb::callable`], [`@jit` fn], [312.681], [1.5× faster],
    [`mapAll`], [`std::function`], [`@jit` fn], [339.663], [1.4× faster],
    [`forAll`], [fn ptr], [`@cfunc`], [35.144], [13.5× faster],
    [`seqFor`], [fn ptr], [`@cfunc`], [34.775], [13.7× faster],
    table.hline(stroke: 1.5pt),
  ),
  caption: [
    Scenario B --- heavier element-wise compute ($sin(x) + cos(x) dot sqrt(|x|+1)$), $N = 2^(21) = 2 thin 097 thin 152$
    sorted by calling strategy. Baseline is plain Python list with a Python function.
    Benchmark ran on a PC with Ryzen 3600 CPU in WSL2 environment.
  ],
) <benchmark_scenario_b_table>

== Other Python libraries

=== CuPy

=== Polars

// https://docs.pola.rs/user-guide/expressions/user-defined-python-functions/#processing-a-whole-series-with-map_batches

=== NumPy

// TODO: mention inspiration from some libraries described above?
=== JAX