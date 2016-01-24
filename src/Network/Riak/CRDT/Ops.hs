module Network.Riak.CRDT.Ops (counterUpdateOp,
                              setUpdateOp, SetOpsComb(..), toOpsComb,
                              mapUpdateOp)
    where

import qualified Network.Riak.Protocol.DtOp as PB
import qualified Network.Riak.Protocol.CounterOp as PB
import qualified Network.Riak.Protocol.SetOp as PBSet

import qualified Network.Riak.Protocol.MapOp                 as PBMap
import qualified Network.Riak.Protocol.MapField              as PBMap
import qualified Network.Riak.Protocol.MapField.MapFieldType as PBMap
import qualified Network.Riak.Protocol.MapUpdate             as PBMap

import qualified Network.Riak.Protocol.MapUpdate.FlagOp as PBFlag

import Network.Riak.CRDT.Types
import Data.Monoid
import Data.Traversable
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.Sequence as Seq
import qualified Data.Set as S
import Data.ByteString.Lazy (ByteString)


counterUpdateOp :: [CounterOp] -> PB.DtOp
counterUpdateOp ops = PB.DtOp { PB.counter_op = Just $ counterOpPB ops,
                                PB.set_op = Nothing,
                                PB.map_op = Nothing
                              }

counterOpPB ops = PB.CounterOp (Just i)
    where CounterInc i = mconcat ops


data SetOpsComb = SetOpsComb { setAdds :: S.Set ByteString,
                               setRemoves :: S.Set ByteString }
             deriving (Show)

instance Monoid SetOpsComb where
    mempty = SetOpsComb mempty mempty
    (SetOpsComb a b) `mappend` (SetOpsComb x y) = SetOpsComb (a<>x) (b<>y)

toOpsComb (SetAdd s) = SetOpsComb (S.singleton s) S.empty
toOpsComb (SetRemove s) = SetOpsComb S.empty (S.singleton s)



setUpdateOp :: [SetOp] -> PB.DtOp
setUpdateOp ops = PB.DtOp { PB.counter_op = Nothing,
                            PB.set_op = Just $ setOpPB ops,
                            PB.map_op = Nothing
                          }

setOpPB :: [SetOp] -> PBSet.SetOp
setOpPB ops = PBSet.SetOp (toSeq adds) (toSeq rems)
    where SetOpsComb adds rems = mconcat . map toOpsComb $ ops
          toSeq = Seq.fromList . S.toList

flagOpPB :: FlagOp -> PBFlag.FlagOp
flagOpPB (FlagSet True)  = PBFlag.ENABLE
flagOpPB (FlagSet False) = PBFlag.DISABLE

registerOpPB :: RegisterOp -> ByteString
registerOpPB (RegisterSet x) = x

mapUpdateOp :: [MapOp] -> PB.DtOp
mapUpdateOp ops = PB.DtOp { PB.counter_op = Nothing,
                            PB.set_op = Nothing,
                            PB.map_op = Just $ mapOpPB ops }

mapOpPB :: [MapOp] -> PBMap.MapOp
mapOpPB ops = PBMap.MapOp rems updates
    where rems    = mempty
          updates = Seq.fromList [ toUpdate f u | MapUpdate f u <- ops ]


toUpdate :: MapPath -> MapValueOp -> PBMap.MapUpdate
toUpdate (MapPath (e :| [])) op     = toUpdate' e (tagOf' op) op
toUpdate (MapPath (e :| (r:rs))) op = toUpdate' e MapMapTag op'
    where op' = MapMapOp (MapUpdate (MapPath (r:|rs)) op)

toUpdate' :: ByteString -> MapEntryTag -> MapValueOp -> PBMap.MapUpdate
toUpdate' f t op = setSpecificOp op (updateNothing f t)

setSpecificOp :: MapValueOp -> PBMap.MapUpdate -> PBMap.MapUpdate
setSpecificOp (MapCounterOp cop) u  = u { PBMap.counter_op  = Just $ counterOpPB [cop] }
setSpecificOp (MapSetOp sop) u      = u { PBMap.set_op      = Just $ setOpPB [sop] }
setSpecificOp (MapRegisterOp rop) u = u { PBMap.register_op = Just $ registerOpPB rop }
setSpecificOp (MapFlagOp fop) u     = u { PBMap.flag_op     = Just $ flagOpPB fop }
setSpecificOp (MapMapOp mop) u      = u { PBMap.map_op      = Just $ mapOpPB [mop] }


updateNothing f t = PBMap.MapUpdate { PBMap.field = toField f t,
                                    PBMap.counter_op = Nothing,
                                    PBMap.set_op = Nothing,
                                    PBMap.register_op = Nothing,
                                    PBMap.flag_op = Nothing,
                                    PBMap.map_op = Nothing }

--toField :: MapField -> PBMap.MapField
toField name t = PBMap.MapField { PBMap.name = name,
                                             PBMap.type' = typ t }
    where typ MapCounterTag  = PBMap.COUNTER
          typ MapSetTag      = PBMap.SET
          typ MapRegisterTag = PBMap.REGISTER
          typ MapFlagTag     = PBMap.FLAG
          typ MapMapTag      = PBMap.MAP
