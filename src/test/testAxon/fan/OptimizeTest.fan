//
// Copyright (c) 2019, SkyFoundry LLC
// Licensed under the Academic Free License version 3.0
//
// History:
//   9 Oct 2019  Brian Frank  Creation
//

using haystack
using axon

**
** OptimizeTest
**
@Js
class OptimizeTest : AxonTest
{

//////////////////////////////////////////////////////////////////////////
// Return
//////////////////////////////////////////////////////////////////////////

  Void testReturn()
  {
    verifyNormalize("(x) => x", "(x) => x")

    verifyNormalize("(x) => return x", "(x) => x")

    verifyNormalize("do return 3; return 4 end",
      """do
           return 3;
           return 4;
         end
         """)

    verifyNormalize("() => do return 3; return 4 end",
      """() => do
           return 3;
           4;
         end
         """)

    // we don't optimize every case...

    verifyNormalize("""() => if (true) return 3 else return 4""",
      """() => if (true) return 3 else return 4""")

    verifyNormalize(
      """(x) => do
           if (x) return 3 else return 4
         end
         """,
      """(x) => do
           if (x) return 3 else return 4;
         end
         """)

     // torture case
    verifyNormalize(
      """(x) => do
           if (x) return 1
           else do
             return 2
           end
           f: () => return 3
           g: () => do
             h: () => return 4
             return 5
             return 6
           end
           return 7
           return 8
         end
         """,
      """(x) => do
           if (x) return 1 else do
             return 2;
           end
           f: () => 3;
           g: () => do
             h: () => 4;
             return 5;
             6;
           end
           return 7;
           8;
         end
         """)
  }

  Void verifyNormalize(Str src, Str expected)
  {
    actual := Parser(Loc.eval, src.in).parse.toStr
    // echo("\n------\n$actual")
    verifyEq(actual, expected)
  }

//////////////////////////////////////////////////////////////////////////
// Dot Calls
//////////////////////////////////////////////////////////////////////////

  Void testDotCall()
  {
    // dot call must evaluate the first argument to determine
    // the dispatch mechanism; but we want to make sure that
    // the first argument isn't evaluated more than once
    verifyEval(
    """do
         x: 0
         foo: (a, b) => a + b
         bar: () => do
           //echo("calling bar x=" + x)
           x = x + 1
           x
         end
         y: bar().foo(7)
         [x, y]
       end""",
       Obj?[n(1), n(8)])


  }

}

