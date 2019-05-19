{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Source
    ( runGUI,
      readTyEnv,
    ) where

import Control.Monad
import Control.Monad.IO.Class
import qualified Graphics.UI.Gtk as Gtk
import Data.IORef
import Control.Lens ((^.), over, _Left)
import Data.Foldable (toList)
import Text.Megaparsec (errorBundlePretty)

import Slay.Core
import Slay.Cairo.Render
import Source.Phaser
import Source.Input (InputEvent(..), Modifier(..))
import qualified Source.NewGen as NG
import qualified Sdam.Parser

runGUI :: NG.Plugin -> IO NG.EditorState -> IO ()
runGUI plugin initEditorState = do
  let pluginInfo = NG.mkPluginInfo plugin
  _ <- Gtk.initGUI
  esRef <- initEditorState >>= newIORef
  window <- createMainWindow pluginInfo esRef
  Gtk.widgetShowAll window
  Gtk.mainGUI

createMainWindow :: NG.PluginInfo -> IORef NG.EditorState -> IO Gtk.Window
createMainWindow pluginInfo esRef = do
  window <- Gtk.windowNew
  _ <- Gtk.on window Gtk.objectDestroy Gtk.mainQuit

  canvas <- createMainCanvas

  -- TODO: PointerMotionHintMask; eventRequestMotions
  Gtk.widgetAddEvents canvas
      [ Gtk.PointerMotionMask
      , Gtk.ButtonPressMask
      ]

  layoutRef :: IORef (Collage NG.Draw)
    <- newIORef (error "layoutRef used before initialization")

  pointerRef :: IORef (Maybe Offset)
    <- newIORef Nothing

  cursorPhaser <- newPhaser 530000 NG.CursorVisible NG.blink
    (\_ -> Gtk.postGUIAsync (Gtk.widgetQueueDraw canvas))

  let
    updateCanvas viewport = do
      es <- liftIO $ readIORef esRef
      let
        lctx =
          NG.LayoutCtx
            { NG._lctxPath = mempty @NG.PathBuilder,
              NG._lctxViewport = viewport,
              NG._lctxPrecBordersAlways = es ^. NG.esPrecBordersAlways,
              NG._lctxRecLayouts = pluginInfo ^. NG.pluginInfoRecLayouts,
              NG._lctxWritingDirection = es ^. NG.esWritingDirection }
        layout = NG.layoutEditorState lctx es
      liftIO $ writeIORef layoutRef layout
      cursorVisible <- liftIO $ phaserCurrent cursorPhaser
      let
        elements = collageElements offsetZero layout
        pathsCursor = NG.findPath elements (es ^. NG.esPointer)
        pathsSelection = NG.selectionPathEditorState es
        paths = NG.Paths {NG.pathsCursor, NG.pathsSelection}
      renderElements
        (NG.withDrawCtx paths cursorVisible)
        (NG.toCairoElementsDraw (toList elements))

    handleInputEvent inputEvent = do
      es <- readIORef esRef
      layout <- readIORef layoutRef
      let
        elements = collageElements offsetZero layout
        rctx =
          NG.ReactCtx
            { NG._rctxFindPath = NG.findPath elements,
              NG._rctxInputEvent = inputEvent,
              NG._rctxNodeFactory = pluginInfo ^. NG.pluginInfoNodeFactory,
              NG._rctxDefaultValues = pluginInfo ^. NG.pluginInfoDefaultValues,
              NG._rctxAllowedFieldTypes = pluginInfo ^. NG.pluginInfoAllowedFieldTypes,
              NG._rctxRecMoveMaps = pluginInfo ^. NG.pluginInfoRecMoveMaps,
              NG._rctxWritingDirection = es ^. NG.esWritingDirection }
      mEs' <- NG.reactEditorState rctx es
      case mEs' of
        Nothing -> do
          print inputEvent
          return False
        Just es' -> do
          atomicWriteIORef esRef es'
          Gtk.widgetQueueDraw canvas
          return True

  void $ Gtk.on canvas Gtk.draw $ do
    w <- liftIO $ Gtk.widgetGetAllocatedWidth  canvas
    h <- liftIO $ Gtk.widgetGetAllocatedHeight canvas
    let viewport = Extents (fromIntegral w) (fromIntegral h)
    updateCanvas viewport

  void $ Gtk.on canvas Gtk.keyPressEvent $ do
    modifier <- Gtk.eventModifier
    keyVal <- Gtk.eventKeyVal
    let
      event = KeyPress (modifier >>= gtkMod) keyVal
      gtkMod = \case
        Gtk.Control -> [Control]
        Gtk.Shift -> [Shift]
        Gtk.Alt -> [Alt]
        _ -> []
    liftIO $ do
      phaserReset cursorPhaser NG.CursorVisible
      handleInputEvent event

  void $ Gtk.on canvas Gtk.motionNotifyEvent $ do
    (x, y) <- Gtk.eventCoordinates
    let (x', y') = (round x, round y)
    liftIO $ atomicWriteIORef pointerRef (Just (Offset x' y'))
    let event = PointerMotion (fromInteger x') (fromInteger y')
    liftIO (handleInputEvent event)

  void $ Gtk.on canvas Gtk.buttonPressEvent $ do
    liftIO (handleInputEvent ButtonPress)

  Gtk.containerAdd window canvas
  Gtk.windowMaximize window
  return window

createMainCanvas :: IO Gtk.DrawingArea
createMainCanvas = do
  canvas <- Gtk.drawingAreaNew
  Gtk.set canvas
    [ Gtk.widgetExpand   Gtk.:= True
    , Gtk.widgetCanFocus Gtk.:= True
    , Gtk.widgetHasFocus Gtk.:= True
    ]
  return canvas


readTyEnv :: FilePath -> IO (Either String NG.Env)
readTyEnv path = do
  tyEnvDesc <- readFile path
  return $ over _Left errorBundlePretty $
    Sdam.Parser.parse
      Sdam.Parser.pEnv
      path
      tyEnvDesc
