module Control.Monad.Gen
  ( module Control.Monad.Gen.Class
  , choose
  , oneOf
  , frequency
  , elements
  , unfoldable
  , suchThat
  ) where

import Prelude

import Control.Monad.Gen.Class (class MonadGen, Size, chooseBool, chooseFloat, chooseInt, resize, sized)
import Control.Monad.Rec.Class (class MonadRec, Step(..), tailRecM)

import Data.Foldable (length)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Monoid.Additive (Additive(..))
import Data.Newtype (alaF)
import Data.Semigroup.Foldable (class Foldable1)
import Data.Tuple (Tuple(..), fst, snd)
import Data.Unfoldable (class Unfoldable, unfoldr)

data LL a = Cons a (LL a) | Nil

-- | Creates a generator that outputs a value chosen from one of two existing
-- | existing generators with even probability.
choose :: forall m a. MonadGen m => m a -> m a -> m a
choose genA genB = chooseBool >>= if _ then genA else genB

-- | Creates a generator that outputs a value chosen from a selection of
-- | existing generators with uniform probability.
oneOf :: forall m f a. MonadGen m => Foldable1 f => f (m a) -> m a
oneOf xs = do
  n <- chooseInt 0 (length xs - 1)
  fromIndex n xs

-- | Creates a generator that outputs a value chosen from a selection of
-- | existing generators, where the selection has weight values for the
-- | probability of choice for each generator. The probability values will be
-- | normalised.
frequency
  :: forall m f a
   . MonadGen m
  => Foldable1 f
  => f (Tuple Number (m a))
  -> m a
frequency xs =
  let
    total = alaF Additive foldMap fst xs
  in
    chooseFloat 0.0 total >>= pick
  where
  pick pos = 
    let
      initial = Tuple 0.0 Nothing
    in 
      snd $ foldl go initial xs
    where
    go (Tuple weight val) (Tuple currWeight currVal) =
      let
        nextWeight = weight + currWeight 
      in 
        if weight <= pos && pos <= nextWeight
          then Tuple nextWeight currVal
          else Tuple nextWeight val

-- | Creates a generator that outputs a value chosen from a selection with
-- | uniform probability.
elements :: forall m f a. MonadGen m => Foldable1 f => f a -> m a
elements xs = do
  n <- chooseInt 0 (length xs - 1)
  pure $ fromIndex n x xs

-- | Creates a generator that produces unfoldable structures based on an
-- | existing generator for the elements.
-- |
-- | The size of the unfoldable will be determined by the current size state
-- | for the generator. To generate an unfoldable structure of a particular
-- | size, use the `resize` function from the `MonadGen` class first.
unfoldable
  :: forall m f a
   . MonadRec m
  => MonadGen m
  => Unfoldable f
  => m a
  -> m (f a)
unfoldable gen = unfoldr unfold <$> sized (tailRecM loopGen <<< Tuple Nil)
  where
  loopGen :: Tuple (LL a) Int -> m (Step (Tuple (LL a) Int) (LL a))
  loopGen = case _ of
    Tuple acc 0 ->
      pure $ Done acc
    Tuple acc n -> do
      x <- gen
      pure $ Loop (Tuple (Cons x acc) (n - 1))
  unfold :: LL a -> Maybe (Tuple a (LL a))
  unfold = case _ of
    Nil -> Nothing
    Cons x xs -> Just (Tuple x xs)

-- | Creates a generator that repeatedly run another generator until its output
-- | matches a given predicate. This will never halt if the predicate always
-- | fails.
suchThat :: forall m a. MonadRec m => MonadGen m => m a -> (a -> Boolean) -> m a
suchThat gen pred = tailRecM go unit
  where
  go :: Unit -> m (Step Unit a)
  go _ = gen <#> \a -> if pred a then Done a else Loop unit

fromIndex :: forall f a. Foldable1 f => Int -> f a -> a
fromIndex i a = fromMaybe a <<< snd <<< (foldl go (Tuple 0 (Just a)))
  where
  go (Tuple ix v) x = Tuple (ix + 1) (if ix == i then Just x else v)
