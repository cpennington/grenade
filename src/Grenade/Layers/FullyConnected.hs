{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
module Grenade.Layers.FullyConnected (
    FullyConnected (..)
  , FullyConnected' (..)
  , randomFullyConnected
  ) where

import           Control.Monad.Random hiding (fromList)

import           Control.DeepSeq (NFData(..))
import           Data.Proxy
import           Data.Serialize
import           Data.Singletons.TypeLits

import qualified Numeric.LinearAlgebra as LA
import           Numeric.LinearAlgebra.Static

import           Grenade.Core

import           Grenade.Layers.Internal.Update

-- | A basic fully connected (or inner product) neural network layer.
data FullyConnected i o = FullyConnected
                        !(FullyConnected' i o)   -- Neuron weights
                        !(FullyConnected' i o)   -- Neuron momentum

data FullyConnected' i o = FullyConnected'
                         !(R o)   -- Bias
                         !(L o i) -- Activations

instance Show (FullyConnected i o) where
  show FullyConnected {} = "FullyConnected"

instance NFData (FullyConnected i o) where
  rnf (FullyConnected x y) = rnf x `seq` rnf y

instance NFData (FullyConnected' i o) where
  rnf (FullyConnected' x y) = rnf x `seq` rnf y

instance (KnownNat i, KnownNat o) => Num (FullyConnected' i o) where
  (+) (FullyConnected' x0 y0) (FullyConnected' x1 y1)  = FullyConnected' (x0 + x1) (y0 + y1)
  (-) (FullyConnected' x0 y0) (FullyConnected' x1 y1)  = FullyConnected' (x0 - x1) (y0 - y1)
  (*) (FullyConnected' x0 y0) (FullyConnected' x1 y1)  = FullyConnected' (x0 * x1) (y0 * y1)
  abs (FullyConnected' x y)  = FullyConnected' (abs x) (abs y)
  signum (FullyConnected' x y)  = FullyConnected' (signum x) (signum y)
  fromInteger x = FullyConnected' (fromInteger x) (fromInteger x)


instance (KnownNat i, KnownNat o) => UpdateLayer (FullyConnected i o) where
  type Gradient (FullyConnected i o) = (FullyConnected' i o)

  runUpdate LearningParameters {..} (FullyConnected (FullyConnected' oldBias oldActivations) (FullyConnected' oldBiasMomentum oldMomentum)) (FullyConnected' biasGradient activationGradient) =
    let (newBias, newBiasMomentum)    = decendVector learningRate learningMomentum learningRegulariser oldBias biasGradient oldBiasMomentum
        (newActivations, newMomentum) = decendMatrix learningRate learningMomentum learningRegulariser oldActivations activationGradient oldMomentum
    in FullyConnected (FullyConnected' newBias newActivations) (FullyConnected' newBiasMomentum newMomentum)

  createRandom = randomFullyConnected

instance (KnownNat i, KnownNat o) => Layer (FullyConnected i o) ('D1 i) ('D1 o) where
  type Tape (FullyConnected i o) ('D1 i) ('D1 o) = S ('D1 i)
  -- Do a matrix vector multiplication and return the result.
  runForwards (FullyConnected (FullyConnected' wB wN) _) (S1D v) = (S1D v, S1D (wB + wN #> v))

  -- Run a backpropogation step for a full connected layer.
  runBackwards (FullyConnected (FullyConnected' _ wN) _) (S1D x) (S1D dEdy) =
          let wB'  = dEdy
              mm'  = dEdy `outer` x
              -- calcluate derivatives for next step
              dWs  = tr wN #> dEdy
          in  (FullyConnected' wB' mm', S1D dWs)

instance (KnownNat i, KnownNat o) => Serialize (FullyConnected i o) where
  put (FullyConnected (FullyConnected' b w) _) = do
    putListOf put . LA.toList . extract $ b
    putListOf put . LA.toList . LA.flatten . extract $ w

  get = do
      let f  = fromIntegral $ natVal (Proxy :: Proxy i)
      b     <- maybe (fail "Vector of incorrect size") return . create . LA.fromList =<< getListOf get
      k     <- maybe (fail "Vector of incorrect size") return . create . LA.reshape f . LA.fromList =<< getListOf get
      let bm = konst 0
      let mm = konst 0
      return $ FullyConnected (FullyConnected' b k) (FullyConnected' bm mm)

randomFullyConnected :: (MonadRandom m, KnownNat i, KnownNat o)
                     => m (FullyConnected i o)
randomFullyConnected = do
    s1    <- getRandom
    s2    <- getRandom
    let wB = randomVector  s1 Uniform * 2 - 1
        wN = uniformSample s2 (-1) 1
        bm = konst 0
        mm = konst 0
    return $ FullyConnected (FullyConnected' wB wN) (FullyConnected' bm mm)
