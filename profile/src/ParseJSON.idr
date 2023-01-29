module ParseJSON

import Derive.Prelude
import JSON
import LexJSON
import Text.Lex
import Text.Parse
import Text.Parse.Res

%language ElabReflection
%default total

0 Rule : Bool -> Type -> Type
Rule b t =
     (xs : List $ Bounded JSToken)
  -> (0 acc : SuffixAcc xs)
  -> Res b JSToken xs JSErr t

array : Bounds -> SnocList JSON -> Rule True JSON

object : Bounds -> SnocList (String,JSON) -> Rule True JSON

value : Rule True JSON
value (B (Lit y) _ :: xs)        _      = Succ y xs
value (B '[' _ :: B ']' _ :: xs) _      = Succ (JArray []) xs
value (B '[' b :: xs)            (SA r) = succ $ array b [<] xs r
value (B '{' _ :: B '}' _ :: xs) _      = Succ (JObject []) xs
value (B '{' b :: xs)            (SA r) = succ $ object b [<] xs r
value (x :: xs) _                       = unexpected x
value [] _                              = eoi

array b sv xs sa@(SA r) = case value xs sa of
  Succ v (B ',' _ :: ys) => succ $ array b (sv :< v) ys r
  Succ v (B ']' _ :: ys) => Succ (JArray $ sv <>> [v]) ys
  Succ v (y       :: ys) => unexpected y
  Succ _ []              => custom b (Unclosed '[')
  Fail (B EOI _)         => custom b (Unclosed '[')
  Fail err               => Fail err

object b sv (B (Lit $ JString l) _ :: B ':' _ :: xs) (SA r) =
  case succ $ value xs r of
    Succ v (B ',' _ :: ys) => succ $ object b (sv :< (l,v)) ys r
    Succ v (B '}' _ :: ys) => Succ (JObject $ sv <>> [(l,v)]) ys
    Succ v (y       :: ys) => unexpected y
    Succ _ []              => custom b (Unclosed '}')
    Fail (B EOI _)         => custom b (Unclosed '}')
    Fail err               => Fail err
object b sv (B (Lit $ JString _) _ :: x :: xs) _ = expected x.bounds ':'
object b sv (x :: xs)                          _ = custom x.bounds ExpectedString
object b sv []                                 _ = eoi

0 Ru : Bool -> Type -> Type
Ru b a = Grammar b () JSToken JSErr a

str : Ru True String
str = terminal $ \case {Lit (JString s) => Just s; _ => Nothing}

lit : Ru True JSON
lit = terminal $ \case
  Lit j  => Just j
  _        => Nothing

val,vals,obj,prs,arr : Ru True JSON

val = lit <|> arr <|> obj

vals = JArray <$> (sepBy (is ',') val <* is ']')

arr = is '[' >>= \_ => vals

pr : Ru True (String,JSON)
pr = [| MkPair (str <* is ':') val |]

prs = JObject <$> (sepBy (is ',') pr <* is '}')

obj = is '{' >>= \_ => prs

export
fastParse : String -> Either JSParseErr JSON
fastParse str = case json str of
  Right ts => case value ts suffixAcc of
    Fail x         => Left x
    Succ v []      => Right v
    Succ v (x::xs) => unexpected x
  Left err => Left err

export
niceParse : String -> Either (ReadError JSToken JSErr) JSON
niceParse str = case json str of
  Right ts => case parse val () ts of
    Left errs => Left $ parseFailed Virtual errs
    Right (_,res,[]) => Right res
    Right (_,res, (x::xs))  => Left (ParseFailed $ singleton $ virtualFromBounded (Unexpected <$> x))
  Left v => Left $ parseFailed Virtual (pure v)

export
testParse : String -> IO ()
testParse s = case fastParse s of
  Right json => putStrLn "Success: \{show json}"
  Left  err  => putStrLn (printParseError s (FC Virtual err.bounds) err.val)
