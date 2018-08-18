#!/bin/bash

export EXT_IMPORTS='
import public "cr_ext/CRForcefield.proto";
import public "cr_ext/CREmitter.proto";
import public "cr_ext/collisionplane.proto";

'

export EXT_DATA='
  repeated CRParticleEmitter cr_emitters = 600;
  repeated CRForceField cr_forcefields = 601;
    repeated CRCollisionPlane cr_collisionplanes = 602;

'