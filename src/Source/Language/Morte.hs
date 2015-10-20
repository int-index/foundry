{-# LANGUAGE TemplateHaskell #-}
module Source.Language.Morte
    ( State
    ) where

import Control.Lens
import Control.Monad
import Data.Char (toLower)
import Data.Functor.Compose
import Data.Singletons
import Data.Foldable
import Data.Maybe
import Data.Monoid
import Data.Biapplicative
import Data.String (fromString)
import Data.Function
import Data.Text (Text)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.Text.Lazy as Text.Lazy
import qualified Morte.Core as M
import qualified Morte.Parser as M.P
import qualified Morte.Import as M.I

import Source.Syntax
import Source.Draw
import Source.Style
import Source.Input
import qualified Source.Input.KeyCode as KeyCode
import Source.Language.Morte.Node

data State = State
  { _stateExpr :: NodeExpr
  , _statePath :: Discard PathExpr }
makeLenses ''State

instance Syntax State where
  blank = blank'
  layout = layout'
  react = react'

blank' :: IO State
blank' = do
  let et = "λ(x : ∀(Nat : *) → ∀(Succ : Nat → Nat) → ∀(Zero : Nat) → Nat) → x (∀(Bool : *) → ∀(True : Bool) → ∀(False : Bool) → Bool) (λ(x : ∀(Bool : *) → ∀(True : Bool) → ∀(False : Bool) → Bool) → x (∀(Bool : *) → ∀(True : Bool) → ∀(False : Bool) → Bool) (λ(Bool : *) → λ(True : Bool) → λ(False : Bool) → False) (λ(Bool : *) → λ(True : Bool) → λ(False : Bool) → True)) (λ(Bool : *) → λ(True : Bool) → λ(False : Bool) → True)"
  _stateExpr <- view noded <$> case M.P.exprFromText et of
    Left  _ -> return $ M.Const M.Star
    Right e -> M.I.load e
  let _statePath = Discard pHere
  return State{..}

getExcess :: Integral n => n -> n -> (n, n)
getExcess vacant actual =
  let
    excess = max 0 (vacant - actual)
    excess1 = excess `quot` 2
    excess2 = excess - excess1
  in (excess1, excess2)

center :: (Integral n, Integral m) => Extents n m -> Op1 (CollageDraw n m)
center (vacantWidth, vacantHeight) collage =
  let
    (width, height) = getExtents collage
    (excessWidth1,  excessWidth2)  = getExcess vacantWidth  width
    (excessHeight1, excessHeight2) = getExcess vacantHeight height
  in collage & pad (excessWidth1, excessHeight1) (excessWidth2, excessHeight2)

align
  :: (Integral n, Integral m)
  => (Op2 n, Op2 m) -> (Extents n m -> Offset n m) -> Op2 (CollageDraw n m)
align adjust move c1 c2 =
  let vacant = adjust <<*>> getExtents c1 <<*>> getExtents c2
  in overlay move (center vacant c1) (center vacant c2)

verticalCenter :: (Integral n, Integral m) => OpN (CollageDraw n m)
verticalCenter = foldr (align (max, \_ _ -> 0) (_1 .~ 0)) mempty

horizontalCenter :: (Integral n, Integral m) => OpN (CollageDraw n m)
horizontalCenter = foldr (align (\_ _ -> 0, max) (_2 .~ 0)) mempty

line :: (Num n, Num m, Ord n, Ord m) => Color -> n -> CollageDraw n m
line color w
  = background color
  $ extend (w, 1)
  $ mempty

pad :: (Num n, Num m, Ord n, Ord m) => Offset n m -> Offset n m -> Op1 (CollageDraw n m)
pad o1 o2 = offset o1 . extend o2

type CollageDraw n m = Collage n m (Draw n m)

layout' :: Extents Int Int -> State -> IO (CollageDraw Int Int)
layout' viewport state = do
  return
    $ background dark1
    $ center viewport
    $ layoutExpr (join pad (5, 5)) pHere (state ^. stateExpr)
  where
    dark1 = RGB 0.2 0.2 0.2
    dark2 = RGB 0.3 0.3 0.3
    dark3 = RGB 0.25 0.25 0.25
    light1 = RGB 0.7 0.7 0.7
    font = Font "Ubuntu" 12 (RGB 1 1 1) FontWeightNormal
    text = textline font
    punct = textline (font { fontColor = light1 })

    sel :: forall q . PathExpr q -> CollageDraw Int Int -> CollageDraw Int Int
    sel path
      | current = outline dark2 . background dark3
      | otherwise = id
      where
        current = Discard path == state ^. statePath

    layoutExpr
      :: Op1 (CollageDraw Int Int)
      -> PathExpr ('LabelSum 'Expr)
      -> NodeExpr
      -> CollageDraw Int Int
    layoutExpr hook path
      = sel path
      . hook
      . onExpr
          layoutConst
          layoutVar
          (layoutLam $ path -@- pExprLam)
          (layoutPi  $ path -@- pExprPi)
          (layoutApp $ path -@- pExprApp)
          layoutEmbed

    layoutConst :: NodeConst -> CollageDraw Int Int
    layoutConst (End c) = case c of
      M.Star -> punct "★"
      M.Box  -> punct "□"

    layoutVar :: NodeVar -> CollageDraw Int Int
    layoutVar (End (M.V txt n)) = text (Text.Lazy.toStrict txt <> i)
      where
        -- TODO: subscript
        i = if n == 0 then "" else "@" <> fromString (show n)

    layoutApp
      :: PathExpr ('LabelProduct 'App)
      -> NodeApp
      -> CollageDraw Int Int
    layoutApp path = withProduct $ \get ->
        [ layoutExpr
            (join pad (5, 5))
            (path -@- pAppExpr1)
            (get SAppExpr1)
        , join pad (5, 5) (layoutExpr
            (outline dark2 . join pad (5, 5))
            (path -@- pAppExpr2)
            (get SAppExpr2))
        ] & horizontalCenter

    layoutLam
      :: PathExpr ('LabelProduct 'Lam)
      -> NodeLam
      -> CollageDraw Int Int
    layoutLam path = withProduct $ \get ->
      let
        maxWidth = (max `on` fst.getExtents) header body
        header =
          [ extend (4, 0) (punct "λ")
          , [ layoutArg
                (join pad (4, 0))
                (path -@- pLamArg)
                (get SLamArg)
            , join pad (4, 0) (punct ":")
            , layoutExpr (join pad (4, 0)) (path -@- pLamExpr1) (get SLamExpr1)
            ] & horizontal
          ] & horizontal
        body = layoutExpr id (path -@- pLamExpr2) (get SLamExpr2)
      in
        [ header
        , join pad (0, 4) (line light1 maxWidth)
        , body
        ] & vertical

    layoutPi
      :: PathExpr ('LabelProduct 'Pi)
      -> NodePi
      -> CollageDraw Int Int
    layoutPi path = withProduct $ \get ->
      let
        maxWidth = (max `on` fst.getExtents) header body
        header =
          [ extend (4, 0) (punct "Π")
          , [ layoutArg
                (join pad (4, 0))
                (path -@- pPiArg)
                (get SPiArg)
            , join pad (4, 0) (punct ":")
            , layoutExpr (join pad (4, 0)) (path -@- pPiExpr1) (get SPiExpr1)
            ] & horizontal
          ] & horizontal
        body = layoutExpr id (path -@- pPiExpr2) (get SPiExpr2)
      in
        [ header
        , join pad (0, 4) (line light1 maxWidth)
        , body
        ] & vertical

    layoutEmbed :: NodeEmbed -> CollageDraw Int Int
    layoutEmbed (End r) = case r of {}

    layoutArg
      :: Op1 (CollageDraw Int Int)
      -> PathExpr ('LabelEnd 'Arg)
      -> NodeArg
      -> CollageDraw Int Int
    layoutArg hook path = sel path . hook . text . unEnd

react' :: ((State -> State) -> IO ()) -> InputEvent -> State -> IO (Maybe State)
react' _asyncReact inputEvent state

  | KeyPress _ keyCode <- inputEvent
  , keyCode == KeyCode.ArrowUp || keyLetter 'k' keyCode
  = return
  $ updatePath
  $ withDiscard pathUp (state ^. statePath)

  | KeyPress _ keyCode <- inputEvent
  , keyCode == KeyCode.ArrowDown || keyLetter 'j' keyCode
  = return
  $ updatePath
  $ withDiscard (pathChild (state ^. stateExpr)) (state ^. statePath)

  | KeyPress mod keyCode <- inputEvent
  , keyCode == KeyCode.ArrowLeft || keyLetter 'h' keyCode
  = return
  $ updatePath
  $ withDiscard
      (if Shift `elem` mod then pathNeighbourL else pathSiblingL)
      (state ^. statePath)

  | KeyPress mod keyCode <- inputEvent
  , keyCode == KeyCode.ArrowRight || keyLetter 'l' keyCode
  = return
  $ updatePath
  $ withDiscard
      (if Shift `elem` mod then pathNeighbourR else pathSiblingR)
      (state ^. statePath)

  | otherwise
  = return Nothing

  where
    updatePath :: Maybe (Discard PathExpr) -> Maybe State
    updatePath mpath = set statePath <$> mpath ?? state

    keyLetter c keyCode = fmap toLower (keyChar keyCode) == Just c

pathNormalize :: Op1 (Discard (Path p))
pathNormalize (Discard path) = fromMaybe (Discard path) (pathSumUp path)

pathUp :: Path p q -> Maybe (Discard (Path p))
pathUp path = pathNormalize <$> pathProductUp path

pathUps :: Path p q -> NonEmpty (Discard (Path p))
pathUps path = Discard path :| maybe [] (toList . withDiscard pathUps) (pathUp path)

pathSumUp :: Path p q -> Maybe (Discard (Path p))
pathSumUp = \case
  (r :@> Here) -> Just (Discard (withSingI (sRelationSumLabel r) Here))
  (r :@> p1) -> withDiscard (\p1' -> Discard (r :@> p1')) <$> pathSumUp p1
  (r :@- p1) -> withDiscard (\p1' -> Discard (r :@- p1')) <$> pathSumUp p1
  Here -> Nothing

pathProductUp :: Path p q -> Maybe (Discard (Path p))
pathProductUp = \case
  (r :@- Here) -> Just (Discard (withSingI (sRelationProductLabel r) Here))
  (r :@- p1) -> withDiscard (\p1' -> Discard (r :@- p1')) <$> pathProductUp p1
  (r :@> p1) -> withDiscard (\p1' -> Discard (r :@> p1')) <$> pathProductUp p1
  Here -> Nothing

pathSumDown :: Path p q -> [Discard (Path p)]
pathSumDown path = case pathTarget path of
  SLabelSum l -> case l of
    SExpr ->
      [ Discard (path -@- pExprConst)
      , Discard (path -@- pExprVar)
      , Discard (path -@- pExprLam)
      , Discard (path -@- pExprPi)
      , Discard (path -@- pExprApp)
      , Discard (path -@- pExprEmbed) ]
  _ -> []

pathProductDown :: Path p q -> [Discard (Path p)]
pathProductDown path = case pathTarget path of
  SLabelProduct l -> case l of
    SLam ->
      [ Discard (path -@- pLamExpr2)
      , Discard (path -@- pLamExpr1)
      , Discard (path -@- pLamArg) ]
    SPi ->
      [ Discard (path -@- pPiExpr2)
      , Discard (path -@- pPiExpr1)
      , Discard (path -@- pPiArg) ]
    SApp ->
      [ Discard (path -@- pAppExpr2)
      , Discard (path -@- pAppExpr1) ]
  _ -> []

pathChild :: Node p -> Path p q -> Maybe (Discard (Path p))
pathChild node path = pathChildren node path ^? _head

pathChildren :: Node p -> Path p q -> [Discard (Path p)]
pathChildren node path = do
  Discard path'  <- pathSumDown path
  Discard path'' <- pathProductDown path'
  guard $ notNullOf (atPath path'') node
  return (Discard path'')

data Direction = L | R

newtype CyclicStep = CyclicStep Bool

pathSibling' :: Direction -> Path p q -> Compose Maybe ((,) CyclicStep) (Discard (Path p))
pathSibling' direction = \case
  (r :@- Here) -> Compose . Just $ case (direction, r) of
    (L, SLamArg)   -> (CyclicStep True,  Discard pLamExpr2)
    (R, SLamArg)   -> (CyclicStep False, Discard pLamExpr1)
    (L, SLamExpr1) -> (CyclicStep False, Discard pLamArg)
    (R, SLamExpr1) -> (CyclicStep False, Discard pLamExpr2)
    (L, SLamExpr2) -> (CyclicStep False, Discard pLamExpr1)
    (R, SLamExpr2) -> (CyclicStep True,  Discard pLamArg)
    (L, SPiArg)    -> (CyclicStep True,  Discard pPiExpr2)
    (R, SPiArg)    -> (CyclicStep False, Discard pPiExpr1)
    (L, SPiExpr1)  -> (CyclicStep False, Discard pPiArg)
    (R, SPiExpr1)  -> (CyclicStep False, Discard pPiExpr2)
    (L, SPiExpr2)  -> (CyclicStep False, Discard pPiExpr1)
    (R, SPiExpr2)  -> (CyclicStep True,  Discard pPiArg)
    (L, SAppExpr1) -> (CyclicStep True,  Discard pAppExpr2)
    (R, SAppExpr1) -> (CyclicStep False, Discard pAppExpr2)
    (L, SAppExpr2) -> (CyclicStep False, Discard pAppExpr1)
    (R, SAppExpr2) -> (CyclicStep True,  Discard pAppExpr1)
  (r :@- p1) -> withDiscard (\p1' -> Discard (r :@- p1')) <$> pathSibling' direction p1
  (r :@> p1) -> withDiscard (\p1' -> Discard (r :@> p1')) <$> pathSibling' direction p1
  Here -> Compose Nothing

pathSiblingL', pathSiblingR' :: Path p q -> Maybe (CyclicStep, Discard (Path p))
pathSiblingL' = getCompose . pathSibling' L
pathSiblingR' = getCompose . pathSibling' R

nonCyclic :: (CyclicStep, a) -> Maybe a
nonCyclic (CyclicStep cyclic, a) = pure a <* guard (not cyclic)

pathSiblingL, pathSiblingR :: Path p q -> Maybe (Discard (Path p))
pathSiblingL path = snd <$> pathSiblingL' path
pathSiblingR path = snd <$> pathSiblingR' path

pathNeighbourL :: Path p q -> Maybe (Discard (Path p))
pathNeighbourL path =
  (getFirst . foldMap First)
  (withDiscard (nonCyclic <=< pathSiblingL') <$> pathUps path)

pathNeighbourR :: Path p q -> Maybe (Discard (Path p))
pathNeighbourR path =
  (getFirst . foldMap First)
  (withDiscard (nonCyclic <=< pathSiblingR') <$> pathUps path)

{-
import Control.Monad
import Data.Foldable
import Data.Sequence (Seq)
import Data.Text (Text)
import qualified Data.Sequence as Seq
import qualified Data.Text.Lazy as Text.Lazy
import Data.Bool
import Data.Maybe
import Data.Monoid
import Data.String (fromString)
import Control.Lens
import Control.Lens.Discard
import Data.IORef

import Source.Syntax
import Source.Input
import Source.Style
import Source.OldLayout
import qualified Source.Input.KeyCode as KeyCode

import qualified Morte.Core as M
import qualified Morte.Parser as M.P
import qualified Morte.Import as M.I

type Path = Seq Int

atPath :: Path -> D'Traversal' (M.Expr a) (Node a)
atPath path h e = case uncons path of
  Nothing -> fmap getNode (h (NodeExpr e))
  Just (p, ps) -> case e of

    M.App f x -> case p of
        0 -> (\f' -> M.App f' x) <$> atPath ps h f
        1 -> (\x' -> M.App f x') <$> atPath ps h x
        _ -> pure e

    M.Lam x _A b -> case p of
        -2 | Seq.null ps
            ->  h (NodeText (Text.Lazy.toStrict x))
           <&> \x' -> M.Lam (Text.Lazy.fromStrict (getNode x')) _A b
        -1 -> (\_A' -> M.Lam x _A' b) <$> atPath ps h _A
        0  -> (\ b' -> M.Lam x _A b') <$> atPath ps h  b
        _ -> pure e

    M.Pi x _A _B -> case p of
        -2 | Seq.null ps
            ->  h (NodeText (Text.Lazy.toStrict x))
           <&> \x' -> M.Pi (Text.Lazy.fromStrict (getNode x')) _A _B
        -1 -> (\_A' -> M.Pi x _A' _B) <$> atPath ps h _A
        0  -> (\_B' -> M.Pi x _A _B') <$> atPath ps h _B
        _ -> pure e

    _ -> pure e


data Node a t where
    NodeText :: Text -> Node a Text
    NodeExpr :: M.Expr a -> Node a (M.Expr a)

getNode :: Node a t -> t
getNode = \case
    NodeText t -> t
    NodeExpr t -> t

getNodeExpr :: Discard (Node a) -> Maybe (M.Expr a)
getNodeExpr (Discard (NodeExpr expr)) = Just expr
getNodeExpr _ = Nothing

data Hole = Blank | Path M.Path

data State = State
    { _stateExpr :: M.Expr Hole
    , _statePath :: Path
    , _statePointer :: Offset
    , _stateHover :: IORef (Maybe Path)
    }

makeLenses ''State

instance Syntax State where

 blank = do
    let et = "λ(x : ∀(Nat : *) → ∀(Succ : Nat → Nat) → ∀(Zero : Nat) → Nat) → x (∀(Bool : *) → ∀(True : Bool) → ∀(False : Bool) → Bool) (λ(x : ∀(Bool : *) → ∀(True : Bool) → ∀(False : Bool) → Bool) → x (∀(Bool : *) → ∀(True : Bool) → ∀(False : Bool) → Bool) (λ(Bool : *) → λ(True : Bool) → λ(False : Bool) → False) (λ(Bool : *) → λ(True : Bool) → λ(False : Bool) → True)) (λ(Bool : *) → λ(True : Bool) → λ(False : Bool) → True)"
    e <- case M.P.exprFromText et of
      Left  _ -> return $ M.Const M.Star
      Right e -> fmap M.absurd <$> M.I.load e
    hoverRef <- newIORef Nothing
    return $ State e Seq.empty (Offset 0 0) hoverRef

 layout viewport state = do
    l <- layout' (uncurry Extents viewport) state
    let mp = locateFirstDecoration (state ^. statePointer) (layoutPaths l)
    writeIORef (state ^. stateHover) mp
    return (migrate (layoutDecorations mp l))

 react _ inputEvent state
  | KeyPress _ keyCode <- inputEvent
  , keyCode == KeyCode.ArrowLeft || keyChar keyCode == Just 'h'
  = return . Just
  $ updatePath
  $ pathNeighbourL (state ^. stateExpr) (state ^. statePath)

  | KeyPress _ keyCode <- inputEvent
  , keyCode == KeyCode.ArrowRight || keyChar keyCode == Just 'l'
  = return . Just
  $ updatePath
  $ pathNeighbourR (state ^. stateExpr) (state ^. statePath)

  | KeyPress _ keyCode <- inputEvent
  , keyCode == KeyCode.ArrowUp || keyChar keyCode == Just 'k'
  = return . Just
  $ updatePath
  $ pathUp (state ^. statePath)

  | KeyPress _ keyCode <- inputEvent
  , keyCode == KeyCode.ArrowDown || keyChar keyCode == Just 'j'
  = return . Just
  $ updatePath
  $ pathChild (state ^. stateExpr) (state ^. statePath)

  | ButtonPress <- inputEvent = do
      mp <- readIORef (state ^. stateHover)
      case mp of
          Nothing   -> return Nothing
          Just path -> return . Just
                     $ state & statePath .~ path

  | PointerMotion x y <- inputEvent
  = return . Just
  $ state & statePointer .~ Offset x y

  | otherwise
  = return Nothing

  where

    updatePath :: Maybe Path -> State
    updatePath mpath = fromMaybe id (set statePath <$> mpath) state

    pathUp :: Path -> Maybe Path
    pathUp path = path ^? _init

    pathChild :: M.Expr a -> Path -> Maybe Path
    pathChild = pathNthChild 0

    pathNthChild :: forall a . Int -> M.Expr a -> Path -> Maybe Path
    pathNthChild n expr path = do
        subexpr <- d'preview (atPath path) expr >>= getNodeExpr
        case subexpr of
            M.App _ _ -> do
                guard (n >= 0 && n <= 1)
                return (path |> n)
            M.Lam _ _ _ -> do
                guard (n >= (-2) && n <= 0)
                return (path |> n)
            M.Pi _ _ _ -> do
                guard (n >= (-2) && n <= 0)
                return (path |> n)
            _ -> Nothing

    pathChildN :: Path -> Maybe Int
    pathChildN path = path ^? _last

    pathSibling :: (Int -> Int) -> M.Expr a -> Path -> Maybe Path
    pathSibling f expr path = do
        n <- pathChildN path
        pathUp path >>= pathNthChild (f n) expr

    pathNeighbour :: (Int -> Int) -> M.Expr a -> Path -> Maybe Path
    pathNeighbour f term path = asum (pathSibling f term <$> pathUps)
      where pathUps = (reverse.toList) (Seq.inits path)

    pathNeighbourL, pathNeighbourR :: M.Expr a -> Path -> Maybe Path
    pathNeighbourL = pathNeighbour (subtract 1)
    pathNeighbourR = pathNeighbour (+ 1)

data LD = LD'Path Path | LD'Decoration (Maybe Path -> Layout Decoration -> Layout Decoration)

pathHere :: Path -> Layout LD -> Layout LD
pathHere = LayoutDecoration . LD'Path

onHoverPath :: (Maybe Path -> Layout Decoration -> Layout Decoration) -> Layout LD -> Layout LD
onHoverPath = LayoutDecoration . LD'Decoration

instance FromDecoration LD where
    fromDecoration d = LD'Decoration (\_ -> LayoutDecoration d)

layoutPaths :: Layout LD -> Layout Path
layoutPaths
    = stripNothingDecoration
    . fmap (\case { LD'Path p -> Just p; _ -> Nothing } )

layoutDecorations :: Maybe Path -> Layout LD -> Layout Decoration
layoutDecorations p
    = layoutAppDecoration
    . stripNothingDecoration
    . fmap (\case { LD'Decoration f -> Just (f p); _ -> Nothing })

layout' :: Extents -> State -> IO (Layout LD)
layout' viewport state = do
    return $ background dark1
           $ centerContainer viewport
           $ vertical [layoutExpr (pad 5 5 5 5) Seq.empty (view stateExpr state)]
  where
    dark1 = RGB 0.2 0.2 0.2
    dark2 = RGB 0.3 0.3 0.3
    dark3 = RGB 0.25 0.25 0.25
    light1 = RGB 0.7 0.7 0.7
    font = Font "Ubuntu" 12 (RGB 1 1 1) FontWeightNormal
    text = layoutText font
    punct = layoutText (font { fontColor = light1 })

    sel :: Path -> Layout LD -> Layout LD
    sel path = hover . sel' . pathHere path
      where
        current = path == state ^. statePath

        sel' | current = border dark2 . background dark3
             | otherwise = id

        -- TODO: border always on top
        hover = onHoverPath $ \case
            Just p | p == path -> pad 1 1 1 1 . border light1 . pad 2 2 2 2
            _ -> id

    line :: Color -> Int -> Layout LD
    line color w
        = background color
        $ pad w 0 1 0
        $ horizontal []

    layoutExpr :: (Layout LD -> Layout LD) -> Path -> M.Expr Hole -> Layout LD
    layoutExpr hook path = sel path . hook . \case
        M.Const c -> layoutConst c
        M.Var   x -> layoutVar   x
        M.Lam x _A  b -> layoutLam path (Text.Lazy.toStrict x) _A  b
        M.Pi  x _A _B -> layoutPi  path (Text.Lazy.toStrict x) _A _B
        M.App f a -> layoutApp path f a
        _ -> text "Can't render"

    layoutConst :: M.Const -> Layout LD
    layoutConst = \case
        M.Star -> punct "★"
        M.Box -> punct "□"

    layoutVar :: M.Var -> Layout LD
    layoutVar (M.V txt n) = text (Text.Lazy.toStrict txt <> i)
      where
        -- TODO: subscript
        i = if n == 0 then "" else "@" <> fromString (show n)

    layoutCorner :: Text -> Path -> Text -> M.Expr Hole -> M.Expr Hole -> Layout LD
    layoutCorner sym path x _A b = vertical
        [ headerBox
        , pad 0 0 4 4 $ line light1 (width headerBox `max` width bodyBox)
        , bodyBox
        ]
      where
        headerBox = horizontal
            [ pad 0 4 0 0 (punct sym)
            , horizontal
              [ sel (path |> (-2)) (pad 4 4 0 0 (text x))
              , pad 4 4 0 0 (punct ":")
              , layoutExpr (pad 4 4 0 0) (path |> (-1)) _A
              ]
            ]
        bodyBox = layoutExpr id (path |> 0) b

    layoutLam = layoutCorner "λ"
    layoutPi  = layoutCorner "Π"

    layoutApp :: Path -> M.Expr Hole -> M.Expr Hole -> Layout LD
    layoutApp path f a = (center . horizontal)
        [ layoutExpr (pad 5 5 5 5) (path |> 0) f
        , (pad 5 5 5 5)
          (layoutExpr (border dark2 . pad 5 5 5 5) (path |> 1) a)
        ]
-}
