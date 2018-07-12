module Foundry.Syn.Common where

import Data.Text (Text)
import Numeric.Natural (Natural)
import Data.Sequence (Seq)
import Data.Vinyl
import Type.Reflection
import Data.Type.Equality

import Control.Lens
import Control.Applicative
import Control.Monad

import Source.Draw
import Source.Input
import Source.Syntax

maybeA :: Alternative f => Maybe a -> f a
maybeA = maybe empty pure

dark1, dark2, dark3, light1, white :: Color
dark1  = RGB 51 51 51
dark2  = RGB 77 77 77
dark3  = RGB 64 64 64
light1 = RGB 179 179 179
white  = RGB 255 255 255

textWithCursor :: s -/ Draw Path => Text -> (CursorBlink -> Maybe Natural) -> Collage s
textWithCursor = textline white font

text :: s -/ Draw Path => Text -> Collage s
text t = textWithCursor t (\_ -> Nothing)

punct :: s -/ Draw Path => Text -> Collage s
punct t = textline light1 font t (\_ -> Nothing)

font :: Font
font = Font "Ubuntu" 12 FontWeightNormal

keyLetter :: Char -> KeyCode -> Bool
keyLetter c keyCode = keyChar keyCode == Just c

keyCodeLetter :: KeyCode -> Char -> InputEvent n -> Bool
keyCodeLetter kc c = \case
  KeyPress [] keyCode -> keyCode == kc || keyLetter c keyCode
  _ -> False

data PathSegment where
  PathSegment :: Eq a => TypeRep a -> a -> PathSegment

instance Eq PathSegment where
  PathSegment t1 a1 == PathSegment t2 a2 =
    case testEquality t1 t2 of
      Nothing -> False
      Just Refl -> a1 == a2

fromPathSegment :: forall a. Typeable a => PathSegment -> Maybe a
fromPathSegment (PathSegment t a) =
  case testEquality t (typeRep @a) of
    Nothing -> Nothing
    Just Refl -> Just a

type Path = Seq PathSegment

data LayoutCtx = LayoutCtx
  { _lctxSelected :: Bool
  , _lctxPath     :: Path
  }

makeLenses ''LayoutCtx

sel :: s -/ Draw Path => LayoutCtx -> Collage s -> Collage s
sel lctx
  = active light1 (lctx ^. lctxPath)
  . if lctx ^. lctxSelected
    then
      substrate (lrtb @Natural 0 0 0 0) (\e ->
        rect nothing (inj dark3) e <>
        rect (lrtb @Natural 1 1 1 1) (inj dark2) e)
    else id

simpleSubreact :: Char -> syn -> Subreact rp la syn
simpleSubreact c syn = do
  KeyPress [Shift] keyCode <- view rctxInputEvent
  guard (keyLetter c keyCode)
  return syn

guardInputEvent :: (InputEvent Int -> Bool) -> React rp la syn
guardInputEvent = guard <=< views rctxInputEvent

class UndoEq a where
  undoEq :: a -> a -> Bool

instance UndoEq (Rec f '[]) where
  undoEq RNil RNil = True

instance (UndoEq (f a), UndoEq (Rec f as))
      => UndoEq (Rec f (a ': as)) where
  undoEq (a1 :& as1) (a2 :& as2) = undoEq a1 a2 && undoEq as1 as2


class SynSelfSelected a where
  synSelfSelected :: a -> Bool
  default synSelfSelected :: SynSelection a sel => a -> Bool
  synSelfSelected = view synSelectionSelf

class SynSelfSelected a => SynSelection a sel | a -> sel where
  synSelection :: Lens' a sel
  synSelectionSelf :: Lens' a Bool
