{-# LANGUAGE CPP #-}
module Data.Conduit.ProcessSpec (spec, main) where

import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Data.Conduit
import qualified Data.Conduit.List as CL
import Data.Conduit.Process
import Control.Concurrent.Async (concurrently)
import qualified Data.ByteString.Lazy as L
import qualified Data.ByteString as S
import System.Exit
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (liftIO)
import Control.Exception (throwIO)

main :: IO ()
main = hspec spec

spec :: Spec
spec = describe "Data.Conduit.Process" $ do
#ifndef WINDOWS
    prop "cat" $ \wss -> do
        let lbs = L.fromChunks $ map S.pack wss
        ((sink, closeStdin), source, Inherited, cph) <- conduitProcess (shell "cat")
        ((), bss) <- concurrently
            (do
                mapM_ yield (L.toChunks lbs) $$ sink
                closeStdin)
            (source $$ CL.consume)
        L.fromChunks bss `shouldBe` lbs
        ec <- waitForConduitProcess cph
        ec `shouldBe` ExitSuccess

    it "closed stream" $ do
        (ClosedStream, source, Inherited, cph) <- conduitProcess (shell "cat")
        bss <- source $$ CL.consume
        bss `shouldBe` []

        ec <- waitForConduitProcess cph
        ec `shouldBe` ExitSuccess

    let sourceCmd :: String -> Source IO S.ByteString
        sourceCmd cmd = do
            (ClosedStream, (source, close), ClosedStream, cph) <- conduitProcess (shell cmd)
            flip addCleanup source $ const $ do
                close
                ec <- waitForConduitProcess cph
                case ec of
                    ExitSuccess -> return ()
                    _ -> liftIO $ throwIO ec

    it "handles sub-process exit code" $ do
        (sourceCmd "exit 0" $$ CL.sinkNull)
                `shouldReturn` ()
        (sourceCmd "exit 11" $$ CL.sinkNull)
                `shouldThrow` (== ExitFailure 11)
        (sourceCmd "exit 12" $$ CL.sinkNull)
                `shouldThrow` (== ExitFailure 12)
#endif
    it "blocking vs non-blocking" $ do
        (ClosedStream, ClosedStream, ClosedStream, cph) <- conduitProcess (shell "sleep 1")

        mec1 <- getConduitProcessExitCode cph
        mec1 `shouldBe` Nothing

        threadDelay 1500000

        mec2 <- getConduitProcessExitCode cph
        mec2 `shouldBe` Just ExitSuccess

        ec <- waitForConduitProcess cph
        ec `shouldBe` ExitSuccess
