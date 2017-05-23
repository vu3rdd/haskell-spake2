{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE NamedFieldPuns #-}

{-|
Module: Crypto.Spake2
Description: Implementation of SPAKE2 key exchange protocol

Say that you and someone else share a secret password, and you want to use
this password to arrange some secure channel of communication. You want:

 * to know that the other party also knows the secret password (maybe
   they're an imposter!)
 * the password to be secure against offline dictionary attacks
 * probably some other things

SPAKE2 is an algorithm for agreeing on a key exchange that meets these
criteria. See [Simple Password-Based Encrypted Key Exchange
Protocols](http://www.di.ens.fr/~pointche/Documents/Papers/2005_rsa.pdf) by
Michel Abdalla and David Pointcheval for more details.

== How it works

=== Preliminaries

Let's say we have two users, user A and user B. They have already agreed on
the following public information:

 * cyclic group, \(G\) of prime order, \(p\)
 * generating element \(g \in G\), such that \(g \neq 1\)
 * hash algorithm to use, \(H\)

__XXX__: jml's current understanding is that all of this is provided by something
like 'Crypto.ECC.Curve_X25519', and generally anything that implements the
'Crypto.ECC.EllipticCurve' typeclass in a sane way. It is possible that this
typeclass is insufficient.

If the connection is asymmetric (e.g. if user A is a client and user B is a
server), then they will also have:

 * two arbitrary elements in \(M, N \in G\), where \(M\) is associated with
   user A and \(N\) with user B.

If the connection is symmetric (e.g. if user A and B are arbitrary peers),
then they will instead have:

 * a single arbitrary element \(S \in G\)

__XXX__: jml's current understanding is that these are indeed arbitrarily chosen,
and are part of the SPAKE2 protocol specialised to a particular use case. i.e.
that these are /not/ provided by 'EllipticCurve' or the like.

And, they also have a secret password, which in theory is an arbitrary bit
string, but for the purposes of this module is an arbitrary /byte/ string.

This password is mapped to a /scalar/ in group \(G\), in a way that's mutually
agreed to both parties. The means of mapping may be public, but the actual
mapped value /must/ be secret.

=== Definitions

__NOTE__: This is jml's best understanding. It's likely to be wrong.

[@order@]: the number of elements in a group.

[@scalar@]: a number between 0 and \(p\) (that is, in \(\mathbb{Z}_{p}\)),
where \(p\) is the order of the group.
Normally written as a lower-case variable, e.g. \(x\) or \(pw\).

[@point@]: a member of the group, \(G\).
Normally written as an upper-case variable, e.g. \(X\) or \(M\).

[@addition@]: the binary operation on points in the group \(G\).
Confusingly, literature often writes this using product notation.
More confusingly, warner and Sc00bz often use addition

[@scalar multiplication@]: adding a point to itself a scalar number of times.
Confusingly, this is often written as \(X^{n}\) where \(X\) is a point and \(n\) a scalar.
More confusingly, sometimes this is written with product notation, i.e. @x * Y@.

[@generator@]: element of a cyclic group, \(g\),
such that all members of the group can be generated by multiplying (group operation) \(g\) with itself.

#protocol#

=== Protocol

==== How we map the password to a scalar

TODO

==== How we exchange information

/This is derived from the paper linked above./

One side, A, initiates the exchange. They draw a random scalar, \(x\), and
matching point, \(X\), from the group. They then "blind" \(X\) by adding it to \(M\)
multiplied by the password in scalar form. Call this \(X^{\star}\).

\[X^{\star} \leftarrow X \cdot M^{pw}\]

to the other side, side B.

Side B does the same thing, except they use \(N\) instead of \(M\) to blind
the result, and they call it \(Y\) instead of \(X\).

\[Y^{\star} \leftarrow Y \cdot N^{pw}\]

After side A receives \(Y^{\star}\), it calculates \(K_A\), which is the last
missing input in calculating the session key.

\[K_A \leftarrow (Y^{\star}/N^{pw})^x\]

That is, \(K_A\) is \(Y^{\star}\) subtracted from \(N\) scalar multiplied by
\(pw\), all of which is scalar multiplied by \(x\).

Side B likewise calculates:

\[K_B \leftarrow (X^{\star}/M^{pw})^y\]

They then both figure out the session key:

\[SK \leftarrow H(A, B, X^{\star}, Y^{\star}, K, pw)\]

Where side A uses \(K_A\) and side B uses \(K_B\). Including \(pw\) in the
session key is what makes this SPAKE2, not SPAKE1.

If both parties were honest and knew the password, the key will be the same on
both sides.

==== How python-spake2 works

- Message to other side is prepended with a single character, @A@, @B@, or
  @S@, to indicate which side it came from
- The hash function for generating the session key has a few interesting properties:
    - uses SHA256 for hashing
    - does not include password or IDs directly, but rather uses /their/ SHA256
      digests as inputs to the hash
    - for the symmetric version, it sorts \(X^{\star}\) and \(Y^{\star}\),
      because neither side knows which is which
- By default, the ID of either side is the empty bytestring

== Open questions

* how are blinded elements turned into bytes to be sent on the wire?
  * how does this relate to establish \(M\), \(N\), and \(S\)
  * does this correspond to 'encodePoint'?

* how are bytes translated back into blinded elements?
  * does this correspond to 'decodePoint'?
* how is the password (a bytestring) turned into a scalar
  * Using HKDF expansion to a length (in bytes) determined by the group, \(n\) + 16
  * What is the relationship between \(n\) and the group?
  * Where does the 16 come from?
  * this cannot correspond to 'decodePoint',
    because there is no way to recover a scalar from a point.
    * Surely it ought to match the way we encode everything else?
    * Is this a sign that the 'EllipticCurveArith' interface isn't what we want?
    * Worse, is it a sign that the underlying implementations aren't what we want?
* how do we determine \(M\), \(N\), \(S\)?
  * does there need to be a well-known, agreed-upon way of turning simple bytestrings into group elements?
  * does this mechanism need to vary by group, or can it be defined in general terms?
* how does endianness come into play?
* what is Shallue-Woestijne-Ulas and why is it relevant?

== Assumptions

* 'curveGenerateKeyPair' generates a point and scalar that we can use in the SPAKE2 protocol
* 'EllipticCurveArith' provides all the operations we need to implement SPAKE2
* We can reasonably implement 'EllipticCurveArith' for "ed25519" so as to match python-spake2's default SPAKE2 protocol parameters.

== References

* [Javascript implementation](https://github.com/bitwiseshiftleft/sjcl/pull/273/), includes long, possibly relevant discussion
* [Python implementation](https://github.com/warner/python-spake2)
* [SPAKE2 random elements](http://www.lothar.com/blog/54-spake2-random-elements/) - blog post by warner about choosing \(M\) and \(N\)
* [Simple Password-Based Encrypted Key Exchange Protocols](http://www.di.ens.fr/~pointche/Documents/Papers/2005_rsa.pdf) by Michel Abdalla and David Pointcheval
* [draft-irtf-cfrg-spake2-03](https://tools.ietf.org/html/draft-irtf-cfrg-spake2-03) - expired IRTF draft for SPAKE2

-}

module Crypto.Spake2
  ( something
  , Password
  , makePassword
  , Protocol
  , makeAsymmetricProtocol
  , makeSymmetricProtocol
  , expandPassword
  , passwordToScalar
  , generateArbitraryElement
  , createSessionKey
  ) where

import Protolude

import Crypto.ECC (EllipticCurve(..))
import Crypto.Hash (HashAlgorithm, hashWith)
import Data.ByteArray (ByteArray, ByteArrayAccess)

import Crypto.Spake2.Groups (expandData)


-- | Do-nothing function so that we have something to import in our tests.
-- TODO: Actually test something genuine and then remove this.
something :: a -> a
something x = x

-- | Shared secret password used to negotiate the connection.
--
-- Constructor deliberately not exported,
-- so that once a 'Password' has been created, the actual password cannot be retrieved by other modules.
--
-- Construct with 'makePassword'.
newtype Password = Password ByteString deriving (Eq, Ord)

-- | Construct a password.
makePassword :: ByteString -> Password
makePassword = Password

-- | Bytes that identify a side of the protocol
newtype SideID = SideID { unSideID :: ByteString } deriving (Eq, Ord, Show)


-- | Convert a user-supplied password into a scalar on a curve.
passwordToScalar :: Proxy curve -> Password -> Scalar curve
passwordToScalar = notImplemented

-- | Use a bytestring to deterministically generate a point on a curve.
generateArbitraryElement :: Proxy curve -> seed -> Point curve
generateArbitraryElement = notImplemented

-- | One side of the SPAKE2 protocol.
data Side curve
  = Side
  { sideID :: SideID -- ^ Bytes identifying this side
  , blind :: Point curve -- ^ Arbitrarily chosen point in the curve
                         -- used by this side to blind outgoing messages.
  }


-- | Relation between two sides in SPAKE2.
-- Can be either symmetric (both sides are the same), or asymmetric.
data Relation a
  = Asymmetric
  { sideA :: a -- ^ Side A. Both sides need to agree who side A is.
  , sideB :: a -- ^ Side B. Both sides need to agree who side B is.
  }
  | Symmetric
  { bothSides :: a -- ^ Description used by both sides.
  }

-- | Everything required for the SPAKE2 protocol.
--
-- Both sides must agree on these values for the protocol to work.
--
-- Construct with 'makeAsymmetricProtocol' or 'makeSymmetricProtocol'.
data Protocol curve hashAlgorithm
  = Protocol
  { proxy :: Proxy curve -- ^ The curve to use for encryption
  , hashAlgorithm :: hashAlgorithm -- ^ Hash algorithm used for generating the session key
  , relation :: Relation (Side curve)  -- ^ How the two sides relate to each other
  }

-- | Construct an asymmetric SPAKE2 protocol.
makeAsymmetricProtocol :: hashAlgorithm -> Proxy curve -> Point curve -> Point curve -> SideID -> SideID -> Protocol curve hashAlgorithm
makeAsymmetricProtocol hashAlgorithm proxy blindA blindB sideA sideB =
  Protocol proxy hashAlgorithm Asymmetric { sideA = Side { sideID = sideA, blind = blindA }
                                          , sideB = Side { sideID = sideB, blind = blindB }
                                          }

-- | Construct a symmetric SPAKE2 protocol.
makeSymmetricProtocol :: hashAlgorithm -> Proxy curve -> Point curve -> SideID -> Protocol curve hashAlgorithm
makeSymmetricProtocol hashAlgorithm proxy blind id =
  Protocol proxy hashAlgorithm (Symmetric Side { sideID = id, blind = blind })


-- | Create a session key based on the output of SPAKE2.
createSessionKey
  :: (EllipticCurve curve, HashAlgorithm hashAlgorithm)
  => Protocol curve hashAlgorithm  -- ^ The protocol used for this exchange
  -> Point curve  -- ^ The message from side A, \(X^{\star}\), or either side if symmetric
  -> Point curve  -- ^ The message from side B, \(Y^{\star}\), or either side if symmetric
  -> Point curve  -- ^ The calculated key material, \(K\)
  -> Password  -- ^ The shared secret password
  -> ByteString  -- ^ A session key to use for further communication
createSessionKey Protocol{proxy, hashAlgorithm, relation} x y k (Password password) =
  hashDigest transcript

  where
    hashDigest :: ByteArrayAccess input => input -> ByteString
    hashDigest thing = show (hashWith hashAlgorithm thing)

    transcript =
      case relation of
        Asymmetric{sideA, sideB} -> mconcat [ hashDigest password
                                            , hashDigest (unSideID (sideID sideA))
                                            , hashDigest (unSideID (sideID sideB))
                                            , encodePoint proxy x
                                            , encodePoint proxy y
                                            , encodePoint proxy k
                                            ]
        Symmetric{bothSides} -> mconcat [ hashDigest password
                                        , hashDigest (unSideID (sideID bothSides))
                                        , symmetricPoints
                                        , encodePoint proxy k
                                        ]

    symmetricPoints =
      let [ firstMessage, secondMessage ] = sort [ encodePoint proxy x, encodePoint proxy y ]
      in firstMessage <> secondMessage

-- | Expand a password using HKDF so that it has a certain number of bytes.
--
-- TODO: jml cannot remember why you might want to call this.
expandPassword :: (ByteArrayAccess bytes, ByteArray output) => Password -> Int -> output
expandPassword (Password bytes) numBytes = expandData "SPAKE2 password" bytes numBytes
