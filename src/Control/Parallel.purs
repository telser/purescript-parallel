module Control.Parallel 
  ( Parallel()
  , inParallel
  , runParallel
  , runParallelWith
  , withCallback
  , par
  , race
  ) where

import Prelude

import Data.Maybe

import Control.Alt
import Control.Alternative
import Control.Plus

import Control.Monad.Eff
import Control.Monad.Eff.Ref
import Control.Monad.Eff.Unsafe

import Control.Monad.Cont.Trans

refs :: forall eff a. Eff (ref :: REF | eff) a -> Eff eff a
refs = unsafeInterleaveEff

-- | Run two asynchronous computations in parallel, using the specified
-- | function to combine their results once both have completed.
par :: forall a b r eff. (a -> b -> r) -> ContT Unit (Eff eff) a -> ContT Unit (Eff eff) b -> ContT Unit (Eff eff) r
par f ca cb = ContT $ \k -> do
  ra <- refs $ newRef Nothing
  rb <- refs $ newRef Nothing
  
  runContT ca $ \a -> do
    mb <- refs $ readRef rb
    case mb of
      Nothing -> refs $ writeRef ra $ Just a
      Just b -> k (f a b)

  runContT cb $ \b -> do
    ma <- refs $ readRef ra
    case ma of
      Nothing -> refs $ writeRef rb $ Just b
      Just a -> k (f a b)

-- | Run two asynchronous computations in parallel, returning the result
-- | from the computation which finishes first.
race :: forall a eff. ContT Unit (Eff eff) a -> ContT Unit (Eff eff) a -> ContT Unit (Eff eff) a
race c1 c2 = ContT $ \k -> do
  done <- refs $ newRef false

  runContT c1 $ \a -> do
    b <- refs $ readRef done
    if b
      then return unit
      else do
        refs $ writeRef done true
        k a

  runContT c2 $ \a -> do
    b <- refs $ readRef done
    if b
      then return unit
      else do
        refs $ writeRef done true
        k a

-- | The `Parallel` type constructor wraps the `ContT` type constructor
-- | and provides type class instances for parallel composition of
-- | computations:
-- |
-- | - The definition of `(<*>)` from `Apply` runs two computations in parallel and applies
-- |   a function when both complete.
-- | - The definition of `(<|>)` from the `Alt` type class runs two computations in parallel
-- |   and returns the result of the computation which completes first.
-- |
-- | Parallel sections of code can be embedded in sequential code by using
-- | the `inParallel` and `runParallel` functions:
-- |
-- | ```purescript
-- | loadModel :: ContT Unit (Eff (ajax :: AJAX)) Model
-- | loadModel = do
-- |   token <- authenticate
-- |   runParallel $
-- |     Model <$> inParallel (get "/products/popular/" token)
-- |           <*> inParallel (get "/categories/all" token)
-- | ```
newtype Parallel eff a = Parallel (ContT Unit (Eff eff) a)

-- | Create a computation to be run in parallel from a computation in the
-- | continuation monad.
-- |
inParallel :: forall eff a. ContT Unit (Eff eff) a -> Parallel eff a
inParallel = Parallel

-- | Create a parallel computation from an action which uses a callback.
-- |
-- | This function is just shorthand for `inParallel <<< ContT`.
withCallback :: forall eff a. ((a -> Eff eff Unit) -> Eff eff Unit) -> Parallel eff a
withCallback = inParallel <<< ContT

-- | Unwrap a parallel computation so that it may be embedded in sequential code,
-- | or run using `runContT`.
runParallel :: forall eff a. Parallel eff a -> ContT Unit (Eff eff) a
runParallel (Parallel c) = c

-- | Run a parallel computation by providing a callback
-- |
-- | This function is just shorthand for `runContT` composed with `runParallel`.
runParallelWith :: forall eff a. (a -> Eff eff Unit) -> Parallel eff a -> Eff eff Unit
runParallelWith k p = runContT (runParallel p) k

instance functorParallel :: Functor (Parallel eff) where
  map f (Parallel c) = Parallel (f <$> c)

instance applyParallel :: Apply (Parallel eff) where
  apply (Parallel f) (Parallel x) = Parallel (par ($) f x)

instance applicativeParallel :: Applicative (Parallel eff) where
  pure a = Parallel $ pure a

instance altParallel :: Alt (Parallel eff) where
  alt (Parallel c1) (Parallel c2) = Parallel (race c1 c2)

instance plusParallel :: Plus (Parallel eff) where
  empty = Parallel $ ContT $ \_ -> return unit

instance alternativeParallel :: Alternative (Parallel eff)
