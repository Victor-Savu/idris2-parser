module Text.Parse.Core

import Data.Bool
import Data.List
import Data.List1
import Data.List.Suffix
import Derive.Prelude
import Text.Parse.Err
import Text.Parse.FC
import Text.Lex.Bounded
import Text.Lex.Core
import Text.Lex.Tokenizer

%language ElabReflection
%default total

--------------------------------------------------------------------------------
--          Parsing Results
--------------------------------------------------------------------------------

||| Result of running a parser.
public export
data Res :
     (strict : Bool)
  -> (t  : Type)
  -> (ts : List $ Bounded t)
  -> (state,e,a : Type)
  -> Type where

  Fail  :
       {0 b : Bool}
    -> {0 state,t,e,a : Type}
    -> {0 ts : List $ Bounded t}
    -> (consumed : Bool)
    -> (err      : List1 $ Bounded $ ParseErr t e)
    -> Res b t ts state e a

  Pure :
       {0 state,t,e,a : Type}
    -> state
    -> (res   : Bounded a)
    -> (toks  : List $ Bounded t)
    -> Res False t toks state e a

  Succ :
       {0 b : Bool}
    -> {0 state,t,e,a : Type}
    -> {0 ts : List $ Bounded t}
    -> state
    -> (res   : Bounded a)
    -> (toks  : List $ Bounded t)
    -> (0 prf : Suffix True toks ts)
    -> Res b t ts state e a

namespace Res
  public export %inline
  fail_ : Bounded (ParseErr t e) -> Res b t ts s e a
  fail_ = Fail False . singleton

  public export %inline
  parseFail : ParseErr t e -> Res b t ts s e a
  parseFail = fail_ . pure
  
  public export %inline
  fail : e -> Res b t ts s e a
  fail = parseFail . Custom
  
  public export %inline
  parseFailLoc : Bounds -> ParseErr t e -> Res b t ts s e a
  parseFailLoc b err = fail_ (MkBounded err b)
  
  public export %inline
  failLoc : Bounds -> e -> Res b t ts s e a
  failLoc b = parseFailLoc b . Custom

public export
merge : Bounded z -> Res b t ts s e a -> Res b t ts s e a
merge x (Succ y res toks prf) = Succ y (x *> res) toks prf
merge x (Pure y res toks)     = Pure y (x *> res) toks
merge x v                     = v

export
succ : Res b t ts s e a -> (0 p : Suffix True ts ts') -> Res b1 t ts' s e a
succ (Fail c err)          p = Fail c err
succ (Pure x res ts)       p = Succ x res ts p
succ (Succ x res toks prf) p = Succ x res toks (prf ~> p)

--------------------------------------------------------------------------------
--          Grammar
--------------------------------------------------------------------------------

public export %tcinline
0 inf : Bool -> Type -> Type
inf False y = y
inf True  y = Inf y

public export
data Grammar :
     (strict : Bool)
  -> (state,t,e,a : Type)
  -> Type where

  Lift :
       {0 state,t,e,a : Type}
    -> (state -> (ts : List $ Bounded t) -> Res b t ts state e a)
    -> Grammar b state t e a

  AppEat :
       {0 state,t,e,a : Type}
    -> Grammar True state t e (a -> b)
    -> Inf (Grammar b2 state t e a)
    -> Grammar True state t e b

  App :
       {0 state,t,e,a : Type}
    -> Grammar b1 state t e (a -> b)
    -> Grammar b2 state t e a
    -> Grammar (b1 || b2) state t e b

  BindEat :
      {0 state,t,e,a : Type}
   -> Grammar True state t e a
   -> Inf (a -> Grammar b2 state t e b)
   -> Grammar True state t e b

  Bind :
      {0 state,t,e,a : Type}
   -> Grammar b1 state t e a
   -> (a -> Grammar b2 state t e b)
   -> Grammar (b1 || b2) state t e b

  ThenEat :
      {0 state,t,e,a : Type}
   -> Grammar True state t e a
   -> Inf (Grammar b2 state t e b)
   -> Grammar True state t e b

  Then :
      {0 state,t,e,a : Type}
   -> Grammar b1 state t e a
   -> Grammar b2 state t e b
   -> Grammar (b1 || b2) state t e b

  Alt :
      {0 state,t,e,a : Type}
   -> Grammar b1 state t e a
   -> Lazy (Grammar b2 state t e a)
   -> Grammar (b1 && b2) state t e a

  Bounds :
      {0 state,t,e,a : Type}
   -> Grammar b state t e a
   -> Grammar b state t e (Bounded a)

  Try :
      {0 state,t,e,a : Type}
   -> Grammar b state t e a
   -> Grammar b state t e a

--------------------------------------------------------------------------------
--          Error Handling
--------------------------------------------------------------------------------

public export %inline
fail_ :
     {0 state,t,e,a : Type}
  -> Bounded (ParseErr t e)
  -> Grammar b state t e a 
fail_ err = Lift $ \_,_ => fail_ err

||| Always fail with the given error
public export %inline
fail : {0 state,t,e,a : Type} -> e -> Grammar b state t e a
fail err = fail_ (pure $ Custom err)

||| Always fail with a message and a location
public export %inline
failLoc : {0 state,t,e,a : Type} -> Bounds -> e -> Grammar b state t e a
failLoc bs err = fail_ (MkBounded (Custom err) bs)

-------------------------------------------------------------------------------
--         Core Parsers
-------------------------------------------------------------------------------

public export %inline
(>>=) :
     {0 state,t,e,a : Type}
  -> {b1 : _}
  -> Grammar b1 state t e a
  -> inf b1 (a -> Grammar b2 state t e b)
  -> Grammar (b1 || b2) state t e b
(>>=) {b1 = True} = BindEat
(>>=) {b1 = False} = Bind

public export %inline
(>>) :
     {0 state,t,e,a : Type}
  -> {b1 : _}
  -> Grammar b1 state t e ()
  -> inf b1 (Grammar b2 state t e a)
  -> Grammar (b1 || b2) state t e a
(>>) {b1 = True}  = ThenEat
(>>) {b1 = False} = Then

public export %inline
(<|>) :
     {0 b1,b2 : Bool}
  -> {0 state,t,e,a : Type}
  -> Grammar b1 state t e a
  -> Lazy (Grammar b2 state t e a)
  -> Grammar (b1 && b2) state t e a
(<|>) = Alt

public export %inline
pure : {0 state,t,e,a : Type} -> (res : a) -> Grammar False state t e a
pure res = Lift $ \s,ts => Pure s (pure res) ts

public export
Functor (Grammar b s t e) where
  map f g = rewrite sym (orFalseNeutral b) in Bind g (pure . f)

public export %tcinline
(<*>) :
     {0 state,t,e,a : Type}
  -> {b1 : Bool}
  -> Grammar b1 state t e (a -> b)
  -> inf b1 (Grammar b2 state t e a)
  -> Grammar (b1 || b2) state t e b
(<*>) {b1 = True}  = AppEat
(<*>) {b1 = False} = App

public export %inline
(*>) :
     {0 b1,b2 : Bool}
  -> {0 state,t,e,a : Type}
  -> Grammar b1 state t e a
  -> Grammar b2 state t e b
  -> Grammar (b1 || b2) state t e b
(*>) x y = Bind x (\_ => y)

public export %inline
(<*) :
     {0 b1,b2 : Bool}
  -> {0 state,t,e,a : Type}
  -> Grammar b1 state t e a
  -> Grammar b2 state t e b
  -> Grammar (b1 || b2) state t e a
(<*) x y = Bind x (y $>)

||| Check whether the next token satisfies a predicate
public export
nextIs : Lazy e -> (t -> Bool) -> Grammar False s t e t
nextIs err f = Lift $ \s,cs => case cs of
  h :: t =>
    if f h.val then Pure s h _ else failLoc h.bounds err
  []     => parseFail EOI

||| Look at the next token in the input
public export
peek : Grammar False s t e t
peek = Lift $ \s,cs => case cs of
  h :: t => Pure s h _
  []     => parseFail EOI

||| Look at the next token in the input
public export
readHead : (t -> Either (ParseErr t e) a) -> Grammar True s t e a
readHead f = Lift $ \s,cs => case cs of
  h :: t => case f h.val of
    Right v  => Succ s (MkBounded v h.bounds) t %search
    Left err => parseFailLoc h.bounds err
  []     => parseFail EOI

||| Look at the next token in the input
public export %inline
terminal : (t -> Maybe a) -> Grammar True s t e a
terminal f = readHead $ \h => case f h of
  Just a  => Right a
  Nothing => Left (Unexpected h)

||| Look at the next token in the input
public export
is : Eq t => t -> Grammar True s t e ()
is x = readHead $ \h => if x == h then Right () else Left (Expected x)

||| Optionally parse a thing, with a default value if the grammar doesn't
||| match. May match the empty input.
export
option :
     {0 state,t,e,a : Type}
  -> (def : a)
  -> Grammar b state t e a
  -> Grammar False state t e a
option def g = rewrite sym (andFalseFalse b) in g <|> pure def

||| Optionally parse a thing, with a default value if the grammar doesn't
||| match. May match the empty input.
export
optional :
     {0 state,t,e,a : Type}
  -> Grammar b state t e a
  -> Grammar False state t e (Maybe a)
optional = option Nothing . map Just

public export
some : Grammar True s t e a -> Grammar True s t e (List1 a)

public export
many : Grammar True s t e a -> Grammar False s t e (List a)

some g = [| g ::: many g |]

many g = map forget (some g) <|> pure []

||| Parse one or more instances of `p` until `end` succeeds, returning the
||| list of values from `p`. Guaranteed to consume input.
export
someTill : 
     (end : Grammar b s t e x)
  -> (p : Grammar True s t e a )
  -> Grammar True s t e (List1 a)

||| Parse zero or more instances of `p` until `end` succeeds, returning the
||| list of values from `p`. Guaranteed to consume input if `end` consumes.
export
manyTill : 
     (end : Grammar b s t e x)
  -> (p : Grammar True s t e a )
  -> Grammar b s t e (List a)

someTill end p = [| p ::: manyTill end p |]

manyTill end p =
  rewrite sym (andTrueNeutral b) in (end $> []) <|> (forget <$> someTill end p)

||| Parse one or more instance of `skip` until `p` is encountered,
||| returning its value.
export
afterSome :
     (skip : Grammar True s t e x)
  -> (p : Grammar b s t e a )
  -> Grammar True s t e a

||| Parse zero or more instance of `skip` until `p` is encountered,
||| returning its value.
export
afterMany :
     (skip : Grammar True s t e x)
  -> (p : Grammar b s t e a )
  -> Grammar b s t e a

afterSome skip p = [| (\_,x => x) skip (afterMany skip p) |]

afterMany skip p = rewrite sym (andTrueNeutral b) in p <|> afterSome skip p

||| Parse one or more things, each separated by another thing.
export
sepBy1 :
     {b : Bool}
  -> (sep : Grammar True s t e s)
  -> (p : Grammar b s t e a)
  ->  Grammar b s t e (List1 a)
sepBy1 {b = True}  sep p = [| p ::: many (sep *> p) |]
sepBy1 {b = False} sep p = [| p ::: many (sep *> p) |]

||| Parse zero or more things, each separated by another thing. May
||| match the empty input.
export
sepBy :
     {b : Bool}
  -> (sep : Grammar True s t e s)
  -> (p : Grammar b s t e a)
  ->  Grammar False s t e (List a)
sepBy sep p = option [] $ forget <$> sepBy1 sep p

||| Parse one or more instances of `p` separated by and optionally terminated by
||| `sep`.
export
sepEndBy1 :
     {b : Bool}
  -> (sep : Grammar True s t e s)
  -> (p : Grammar b s t e a)
  ->  Grammar b s t e (List1 a)
sepEndBy1 sep p = rewrite sym (orFalseNeutral b) in sepBy1 sep p <* optional sep

||| Parse zero or more instances of `p`, separated by and optionally terminated
||| by `sep`. Will not match a separator by itself.
export
sepEndBy :
     {b : Bool}
  -> (sep : Grammar True s t e s)
  -> (p : Grammar b s t e a)
  ->  Grammar False s t e (List a)
sepEndBy sep p = option [] $ forget <$> sepEndBy1 sep p

||| Parse one or more instances of `p`, separated and terminated by `sep`.
export
endBy1 :
     (sep : Grammar True s t e s)
  -> (p : Grammar b s t e a)
  ->  Grammar True s t e (List1 a)
endBy1 sep p = some $ rewrite sym (orTrueTrue b) in p <* sep

export
endBy :
     (sep : Grammar True s t e s)
  -> (p : Grammar b s t e a)
  ->  Grammar False s t e (List a)
endBy sep p = option [] $ forget <$> endBy1 sep p

||| Parse an instance of `p` that is between `left` and `right`.
export %inline
between :
     (left : Grammar True s t e l)
  -> (right : Grammar True s t e r)
  -> (p : Grammar b s t e a)
  -> Grammar True s t e a
between left right contents = left *> contents <* right

prs :
     {0 state,t,e,a : Type}
  -> Grammar b state t e a
  -> state
  -> (consumed : Bool)
  -> (ts : List $ Bounded t)
  -> (0 acc : SuffixAcc ts)
  -> Res b t ts state e a
prs (Lift f) s1 c1 ts1 _ = case f s1 ts1 of
  Fail c2 err         => Fail (c1 || c2) err
  Pure x res ts1      => Pure x res ts1
  Succ x res toks prf => Succ x res toks prf

prs (App x y) s1 c1 ts1 (Access rec) = case prs x s1 c1 ts1 (Access rec) of
  Succ s2 rf ts2 p2 => case prs y s2 True ts2 (rec ts2 p2) of
    Fail c2 err       => Fail c2 err
    Pure s3 ra ts2    => Succ s3 (rf <*> ra) ts2 p2
    Succ s3 ra ts3 p3 => Succ s3 (rf <*> ra) ts3 (p3 ~> p2)
  Pure s2 rf ts1 => case prs y s2 c1 ts1 (Access rec) of
    Fail c2 err       => Fail c2 err
    Pure s3 ra ts1    => Pure s3 (rf <*> ra) ts1
    Succ s3 ra ts3 p3 => Succ s3 (rf <*> ra) ts3 p3
  Fail c2 err => Fail c2 err

prs (AppEat x y) s1 c1 ts1 (Access rec) = case prs x s1 c1 ts1 (Access rec) of
  Succ s2 rf ts2 p2 => case prs y s2 True ts2 (rec ts2 p2) of
    Fail c2 err       => Fail c2 err
    Pure s3 ra ts2    => Succ s3 (rf <*> ra) ts2 p2
    Succ s3 ra ts3 p3 => Succ s3 (rf <*> ra) ts3 (p3 ~> p2)
  Fail c2 err => Fail c2 err

prs (BindEat x y) s1 c1 ts1 (Access rec) = case prs x s1 c1 ts1 (Access rec) of
  Succ s2 res ts2 p => merge res $ succ (prs (y res.val) s2 True ts2 (rec ts2 p)) p
  Fail c2 err       => Fail c2 err

prs (Bind x y) s1 c1 ts1 (Access rec) = case prs x s1 c1 ts1 (Access rec) of
  Succ s2 res ts2 p => merge res $ succ (prs (y res.val) s2 True ts2 (rec ts2 p)) p
  Pure s2 res ts1   => merge res $ prs (y res.val) s2 c1 ts1 (Access rec)
  Fail c2 err       => Fail c2 err

prs (ThenEat x y) s1 c1 ts1 (Access rec) = case prs x s1 c1 ts1 (Access rec) of
  Succ s2 res ts2 p => merge res $ succ (prs y s2 True ts2 (rec ts2 p)) p
  Fail c2 err       => Fail c2 err

prs (Then x y) s1 c1 ts1 (Access rec) = case prs x s1 c1 ts1 (Access rec) of
  Succ s2 res ts2 p => merge res $ succ (prs y s2 True ts2 (rec ts2 p)) p
  Pure s2 res ts1   => merge res $ prs y s2 c1 ts1 (Access rec)
  Fail c2 err       => Fail c2 err

prs (Alt x y) s1 c1 ts1 acc = case prs x s1 False ts1 acc of
  Succ s2 res ts2 p => Succ s2 res ts2 p
  Pure s2 res ts1   => Pure s2 res ts1
  Fail True err     => Fail True err
  Fail {b = b1} False err  => case prs y s1 False ts1 acc of
    Succ s2 res ts2 p => Succ s2 res ts2 p
    Pure s2 res ts2   => rewrite andFalseFalse b1 in Pure s2 res ts2
    Fail True err2    => Fail True err2
    Fail False err2   => Fail c1 $ err ++ err2

prs (Bounds x) s1 c1 ts1 acc = case prs x s1 c1 ts1 acc of
  Succ s2 res ts2 p => Succ s2 (MkBounded res res.bounds) ts2 p
  Pure s2 res ts2   => Pure s2 (MkBounded res res.bounds) ts2
  Fail c2 err       => Fail c2 err

prs (Try x) s1 c1 ts1 acc = case prs x s1 c1 ts1 acc of
  Fail _ err => Fail False err
  res        => res


export
parse :
     {0 state,t,e,a : Type}
  -> Grammar b state t e a
  -> state
  -> (ts : List $ Bounded t)
  -> Either (List1 $ Bounded $ ParseErr t e) (state, a, List $ Bounded t)
parse g s ts = case prs g s False ts (ssAcc _) of
  Fail _ errs         => Left errs
  Pure x res ts       => Right (x, res.val, ts)
  Succ x res toks prf => Right (x, res.val, toks)

--------------------------------------------------------------------------------
--          Combining Lexers and Parsers
--------------------------------------------------------------------------------

filterOnto :
     List (Bounded t)
  -> (t -> Bool)
  -> SnocList (Bounded t)
  -> List (Bounded t)
filterOnto xs f (sx :< x) =
  if f x.val then filterOnto (x :: xs) f sx else filterOnto xs f sx
filterOnto xs f [<]       = xs

export
lexAndParse :
     {0 state,t,e,a : Type}
  -> Origin
  -> Tokenizer t
  -> (keep : t -> Bool)
  -> Grammar b state t e a
  -> state
  -> String
  -> Either (ReadError t e) (state, a)
lexAndParse orig tm keep gr s str = case lex tm str of
  TR l c st EndInput _ _ => case parse gr s (filterOnto [] keep st) of
    Left x          => Left $ parseFailed orig x
    Right (s2,a,[]) => Right (s2,a)
    Right (s2,a,ts) => Right (s2,a)
  TR l c st r _ _ => Left (LexFailed (FC orig $ MkBounds l c l (c+1)) r)
