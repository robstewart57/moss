--------------------------------------------------------------------------------
-- Haskell client for Moss                                                    --
-- Copyright (c) 2018 Michael B. Gale (m.gale@warwick.ac.uk)                  --
--------------------------------------------------------------------------------

module Stanford.Moss (
    MossCfg(..),
    defaultMossCfg,

    Language(..),
    Moss,
    liftIO,

    withMoss,
    addBaseFile,
    addFile,
    addFilesForStudent,
    query
) where

--------------------------------------------------------------------------------

import Control.Exception
import Control.Monad.State

import Data.Monoid

import Network.Simple.TCP

import System.IO
import System.PosixCompat

import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C

--------------------------------------------------------------------------------

-- | Represents the configuration for a Moss connection.
data MossCfg = MossCfg {
    mossServer     :: HostName,
    mossPort       :: ServiceName,
    mossUser       :: BS.ByteString,
    mossDir        :: Maybe FilePath,
    mossX          :: Bool,
    mossMaxMatches :: Int,
    mossShow       :: Bool,
    mossLanguage   :: Language
}

-- | 'defaultMossCfg' is the default configuration for a Moss connection.
defaultMossCfg :: MossCfg
defaultMossCfg = MossCfg {
    mossServer     = "moss.stanford.edu",
    mossPort       = "7690",
    mossUser       = "",
    mossDir        = Nothing,
    mossX          = False,
    mossMaxMatches = 250,
    mossShow       = True,
    mossLanguage   = Haskell
}

--------------------------------------------------------------------------------

-- | Enumerates programming languages supported by Moss.
data Language
    = C
    | CPP
    | Java
    | CSharp
    | Python
    | VisualBasic
    | Javascript
    | FORTRAN
    | ML
    | Haskell
    | Lisp
    | Scheme
    | Pascal
    | Modula2
    | Ada
    | Perl
    | TCL
    | Matlab
    | VHDL
    | Verilog
    | Spice
    | MIPS
    | A8086
    | HCL2
    deriving (Enum)

instance Show Language where
    show C       = "c"
    show CPP     = "cc"
    show Java    = "java"
    show ML      = "ml"
    show Pascal  = "pascal"
    show Ada     = "ada"
    show Lisp    = "lisp"
    show Scheme  = "scheme"
    show Haskell = "haskell"
    show FORTRAN = "fortran"

--------------------------------------------------------------------------------

-- | Represents the state of a Moss connection.
data MossSt = MossSt {
    mossSocket  :: Socket,
    mossCounter :: Int,
    mossCfg     :: MossCfg
}

type Moss = StateT MossSt IO

-- | 'sendCmd' @socket bytestring@ sends @bytestring@ as a command over the
-- connection represented by @socket@.
sendCmd :: Socket -> BS.ByteString -> IO ()
sendCmd s xs = do
    putStr "Send: "
    putStrLn (show xs)
    send s (xs <> "\n")

-- | 'withMoss' @cfg m@ runs a computation @m@ using a Moss connection whose
-- configuration is reprsented by @cfg@.
withMoss :: MossCfg -> Moss a -> IO a
withMoss (cfg@MossCfg {..}) m =
    connect mossServer mossPort $ \(s, addr) -> do
        sendCmd s ("moss " <> mossUser)
        sendCmd s ("X " <> C.pack (show (fromEnum mossX)))
        sendCmd s ("maxmatches " <> C.pack (show mossMaxMatches))
        sendCmd s ("language " <> C.pack (show mossLanguage))

        ls <- recv s 1024

        case ls of
            Nothing -> error "No data received."
            Just "no" -> do
                sendCmd s "end"
                error "Language not supported"
            Just _ -> do
                putStrLn "Language supported."
                r <- evalStateT m (MossSt s 1 cfg)
                sendCmd s "end"
                return r

{-send = withSocketsDo $ do
    h <- connectTo mossServer mossPort
    hClose h-}

-- | 'uploadFile' @index name path@ uploads a file located at @path@ to Moss
-- and assigns it to the collection of files at @index@ (e.g. representing
-- a student) with the name given by @name@.
uploadFile :: Int -> String -> FilePath -> Moss ()
uploadFile i dn fp = do
    s <- gets mossSocket
    MossCfg{..} <- gets mossCfg

    liftIO $ do
        size <- fileSize <$> getFileStatus fp
        sendCmd s ( "file "
             <> C.pack (show i) <> " "
             <> C.pack (show mossLanguage) <> " "
             <> C.pack (show size) <> " "
             <> C.pack dn)

        xs <- BS.readFile fp
        send s xs

-- | 'addBaseFile' @file@ adds @file@ as part of the skeleton code.
addBaseFile :: String -> FilePath -> Moss ()
addBaseFile = uploadFile 0

-- | 'addFile' @name file@ adds @file@ as a submission to Moss with @name@.
addFile :: String -> FilePath -> Moss ()
addFile desc fp = do
    st <- get
    uploadFile (mossCounter st) desc fp
    put $ st { mossCounter = mossCounter st + 1 }

-- | 'addFilesForStudent' @filesWithNames@ uploads multiple files for
-- the same student. I.e. in the Moss submission they will share the same ID.
addFilesForStudent :: [(String, FilePath)] -> Moss ()
addFilesForStudent fs = do
    st <- get
    forM_ fs $ \(dn,fn) ->
        uploadFile (mossCounter st) dn fn
    put $ st { mossCounter = mossCounter st + 1 }

-- | 'query' @comment@ runs the plagiarism check on all submitted files
query :: BS.ByteString -> Moss (Maybe BS.ByteString)
query cmt = do
    s <- gets mossSocket
    liftIO $ do
        putStrLn "Querying, this may take several minutes..."
        sendCmd s ("query 0 " <> cmt)
        recv s 1024

--------------------------------------------------------------------------------
