module LexJSON

import JSON
import Derive.Prelude
import Text.Lex
import Text.Parse.Err

%language ElabReflection
%default total

public export
data JSToken : Type where
  Symbol   : Char -> JSToken
  Lit      : JSON -> JSToken

%runElab derive "JSToken" [Show,Eq]

public export %inline
fromChar : Char -> JSToken
fromChar = Symbol

export
Interpolation JSToken where
  interpolate (Symbol c) = show c
  interpolate (Lit x)  = "'\{show x}'"

public export
data JSErr : Type where
  ExpectedString  : JSErr
  InvalidEscape   : JSErr
  Unclosed        : Char -> JSErr
  Unknown         : Char -> JSErr

%runElab derive "JSErr" [Show,Eq]

export
Interpolation JSErr where
  interpolate (Unclosed c)    = "Unclosed \{show c}"
  interpolate (Unknown c)     = "Unknown token: \{show c}"
  interpolate ExpectedString  = "Expected string literal"
  interpolate InvalidEscape   = "Invalid escape sequence"

public export %tcinline
0 JSParseErr : Type
JSParseErr = Bounded (ParseError JSToken JSErr)

strLit : SnocList Char -> JSToken
strLit = Lit . JString . cast

str : SnocList Char -> AutoTok False Char JSToken
str sc ('\\' :: c  :: xs) = case c of
  '"'  => str (sc :< '"') xs
  'n'  => str (sc :< '\n') xs
  'f'  => str (sc :< '\f') xs
  'b'  => str (sc :< '\b') xs
  'r'  => str (sc :< '\r') xs
  't'  => str (sc :< '\t') xs
  '\\' => str (sc :< '\\') xs
  '/'  => str (sc :< '/') xs
  'u'  => case xs of
    w :: x :: y :: z :: t' =>
      if isHexDigit w && isHexDigit x && isHexDigit y && isHexDigit z
        then
          let c := cast $ hexDigit w * 0x1000 +
                          hexDigit x * 0x100 +
                          hexDigit y * 0x10 +
                          hexDigit z 
           in str (sc :< c) t'
        else Succ (strLit sc) ('\\'::'u'::w::x::y::z::t')
    _    => Succ (strLit sc) ('\\'::'u'::xs)
  _    => Succ (strLit sc) ('\\'::c::xs)
str sc ('"'  :: xs) = Succ (strLit sc) xs
str sc (c    :: xs) = str (sc :< c) xs
str sc []           = Fail

term : Tok True Char JSToken
term (x :: xs) = case x of
  ',' => Succ ',' xs
  '"' => str [<] xs
  ':' => Succ ':' xs
  '[' => Succ '[' xs
  ']' => Succ ']' xs
  '{' => Succ '{' xs
  '}' => Succ '}' xs
  'n' => case xs of
    'u' :: 'l' :: 'l' :: t => Succ (Lit JNull) t
    _                      => Fail
  't' => case xs of
    'r' :: 'u' :: 'e' :: t => Succ (Lit $ JBool True) t
    _                      => Fail
  'f' => case xs of
    'a' :: 'l' :: 's' :: 'e' :: t => Succ (Lit $ JBool False) t
    _                             => Fail
  d   => suffix (Lit . JNumber . cast . cast {to = String}) $
         number {pre = [<]} (d :: xs) @{Same}
  
term []        = Fail

toErr : (l,c : Nat) -> Char -> List Char -> Either JSParseErr a
toErr l c '"'  cs = custom (oneChar l c) (Unclosed '"')
toErr l c '\\' ('u' :: t) =
  custom (BS l c l (c + 2 + min 4 (length t))) InvalidEscape
toErr l c '\\' (h :: t)   = custom (BS l c l (c + 2)) InvalidEscape
toErr l c x   cs = custom (oneChar l c) (Unknown x)

go :
     SnocList (Bounded JSToken)
 -> (l,c   : Nat)
 -> (cs    : List Char)
 -> (0 acc : SuffixAcc cs)
 -> Either JSParseErr (List (Bounded JSToken))
go sx l c ('\n' :: xs) (SA rec) = go sx (l+1) 0 xs rec
go sx l c (x :: xs)    (SA rec) =
  if isSpace x
     then go sx l (c+1) xs rec
     else case term (x::xs) of
       Succ t xs' @{prf} =>
         let c2 := c + toNat prf
             bt := bounded t l c l c2
          in go (sx :< bt) l c2 xs' rec
       Fail => toErr l c x xs
go sx l c [] _ = Right (sx <>> [])

export
json : String -> Either JSParseErr (List (Bounded JSToken))
json s = go [<] 0 0 (unpack s) suffixAcc
