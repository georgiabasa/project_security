(* *********************************************************************)
(*                                                                     *)
(*            The CertiKOS Certified Kit Operating System              *)
(*                                                                     *)
(*                   The FLINT Group, Yale University                  *)
(*                                                                     *)
(*  Copyright The FLINT Group, Yale University.  All rights reserved.  *)
(*  This file is distributed under the terms of the Yale University    *)
(*  Non-Commercial License Agreement.                                  *)
(*                                                                     *)
(* *********************************************************************)

(* *********************************************************************)
(*                                                                     *)
(*              Load and Store Semantics for Primitives                *)
(*                                                                     *)
(*          Ronghui Gu <ronghui.gu@yale.edu>                           *)
(*                                                                     *)
(*          Yale Flint Group                                           *)
(*                                                                     *)
(* *********************************************************************)

(** This file defines the load and store semantics for primitives at all layers*)

Require Import Coqlib.
Require Import Maps.
Require Import Globalenvs.
Require Import ASTExtra.
Require Import AsmX.
Require Import Values.
Require Import Memory.
Require Import Events.
Require Import LAsm.
Require Import AuxStateDataType.
Require Import Constant.
Require Import FlatMemory.
Require Import GlobIdent.
Require Import Integers.
Require Import CommonTactic.
Require Import AuxLemma.
Require Import AsmImplLemma.
Require Import Observation.

Require Import liblayers.logic.PTreeModules.
Require Import liblayers.logic.LayerLogicImpl.
Require Import liblayers.compcertx.ClightModules.
Require Import liblayers.compat.CompatLayers.
Require Import liblayers.compat.CompatClightSem.
Require Import liblayers.compcertx.MemWithData.

Require Import AbstractDataType.
Require Import HostAccess1.
Require Import GuestAccessIntel1.
Require Export LoadStoreDef.

Section Load_Store.

  Context `{Hobs: Observation}.
  Context `{Hmem: Mem.MemoryModel}.
  Context `{Hmwd: UseMemWithData mem}.
  Context `{HD: CompatData(Obs:=Obs) RData}.

  Notation HDATAOps := (cdata (cdata_ops := data_ops) RData).

  Context `{trap_inv: TrapinfoSetInvariant (Obs:=Obs) (data_ops := data_ops)}.
  Context `{flatmem_store: RData -> memory_chunk -> Z -> val -> option (cdata RData)}.
  
  Section GE.
    
    Context {F V} (ge: Genv.t F V).
    
    Definition exec_loadex1 (chunk: memory_chunk) (m: mwd HDATAOps)
               (a: addrmode) (rs: regset) (rd: preg) := 
      let adt:= (snd m) in
      match (eval_addrmode ge a rs) with
        | Vptr b ofs => 
          match (ikern adt, ihost adt) with
            | (true, true) => Asm.exec_load ge chunk m a rs rd
            | _ => Stuck     
          end
        | Vint adr => 
          match (ihost adt, pg adt) with
            | (true, true) => exec_host_load1 ge adr chunk m rs rd
            | (false, _) => exec_guest_intel_load1 ge adr chunk m rs rd                                         
            | _ => Stuck
          end
        | _ => Stuck
      end.

    Definition exec_storeex1 (chunk: memory_chunk) (m: mwd HDATAOps)
               (a: addrmode) (rs: regset) (rd: preg) (destroyed: list preg) := 
      let adt:= (snd m) in
      match  (eval_addrmode ge a rs) with
        | Vptr b ofs => 
          match (ikern adt, ihost adt) with
            | (true, true) => Asm.exec_store ge chunk m a rs rd destroyed
            | _ => Stuck     
          end
        | Vint adr => 
          match (ihost adt, pg adt) with
            | (true, true) => exec_host_store1 (flatmem_store:= flatmem_store) ge adr chunk m rs rd destroyed
            | (false, _) => exec_guest_intel_store1 (flatmem_store:= flatmem_store) ge adr chunk m rs rd destroyed                                         
            | _ => Stuck
          end
        | _ => Stuck
      end.

      Local Existing Instance Asm.mem_accessors_default.
      Local Existing Instance AsmX.mem_accessors_default_invariant.
      
      Lemma exec_loadex1_high_level_invariant:
        forall adr chunk m rs rd rs' m',
          exec_loadex1 chunk m adr rs rd = Next rs' m' ->
          high_level_invariant (snd m) ->
          high_level_invariant (snd m').
      Proof.
        unfold exec_loadex1. intros until m'.
        destruct (eval_addrmode ge adr rs); try discriminate.
        * destruct (ihost (snd m)); try discriminate.
          destruct (pg (snd m)); try discriminate.
        + eapply exec_host_load1_high_level_invariant; eauto.
        + eapply exec_guest_intel_load1_high_level_invariant; eauto.
          * destruct (ikern (snd m)); try discriminate.
            destruct (ihost (snd m)); try discriminate.
            unfold Asm.exec_load. 
            destruct (Mem.loadv chunk m (eval_addrmode ge adr rs)); 
              try discriminate. congruence.
      Qed.

      Lemma exec_loadex1_asm_invariant:
        forall chunk rd,
        forall TYP: subtype (type_of_chunk chunk) (typ_of_preg rd) = true,
        forall adr m rs rs' m',
          exec_loadex1 chunk m adr rs rd = Next rs' m' ->
          AsmX.asm_invariant ge rs m ->
          AsmX.asm_invariant ge rs' m'.
      Proof.
        unfold exec_loadex1. intros until m'.
        destruct (eval_addrmode ge adr rs); try discriminate.
        * destruct (ihost (snd m)); try discriminate.
          destruct (pg (snd m)); try discriminate.
        + eapply exec_host_load1_asm_invariant; eauto.
        + intros; eapply exec_guest_intel_load1_asm_invariant; eauto.
          * destruct (ikern (snd m)); try discriminate.
            destruct (ihost (snd m)); try discriminate.
            intros; eapply exec_load_invariant; eauto.
      Qed.

      Lemma exec_loadex1_low_level_invariant:
        forall adr chunk m rs rd rs' m',
          exec_loadex1 chunk m adr rs rd = Next rs' m' ->
          AsmX.asm_invariant ge rs m ->
          CompatData.low_level_invariant (Mem.nextblock m) (snd m) ->
          CompatData.low_level_invariant (Mem.nextblock m') (snd m').
      Proof.
        unfold exec_loadex1. intros until m'.
        destruct (eval_addrmode ge adr rs); try discriminate.
        * destruct (ihost (snd m)); try discriminate.
          destruct (pg (snd m)); try discriminate.
        + eapply exec_host_load1_low_level_invariant; eauto.
        + intros; eapply exec_guest_intel_load1_low_level_invariant; eauto.
          * destruct (ikern (snd m)); try discriminate.
            destruct (ihost (snd m)); try discriminate.
            unfold Asm.exec_load. 
            destruct (Mem.loadv chunk m (eval_addrmode ge adr rs)); try discriminate.
            congruence.
      Qed.

      Context {flat_inv: FlatmemStoreInvariant (data_ops := data_ops) (flatmem_store:= flatmem_store)}.

      Lemma exec_storeex1_high_level_invariant:
        forall adr chunk m rs rd des rs' m',
          exec_storeex1 chunk m adr rs rd des = Next rs' m' ->
          high_level_invariant (snd m) ->
          high_level_invariant (snd m').
      Proof.
        unfold exec_storeex1. intros until m'.
        destruct (eval_addrmode ge adr rs); try discriminate.
        * destruct (ihost (snd m)); try discriminate.
          destruct (pg (snd m)); try discriminate.
        + eapply exec_host_store1_high_level_invariant; eauto.
        + eapply exec_guest_intel_store1_high_level_invariant; eauto.
          * destruct (ikern (snd m)); try discriminate.
            destruct (ihost (snd m)); try discriminate.
            unfold Asm.exec_store. 
            destruct (Mem.storev chunk m (eval_addrmode ge adr rs) (rs rd)) eqn:Heqo; 
              try discriminate.
            destruct (eval_addrmode ge adr rs); try discriminate.
            lift_unfold. 
            destruct Heqo as [? DATA].
            unfold π_data in DATA. simpl in * |- *. congruence.
      Qed.

      Lemma exec_storeex1_asm_invariant:
        forall chunk rd,
        forall adr m des rs rs' m',
          exec_storeex1 chunk m adr rs rd des = Next rs' m' ->
          AsmX.asm_invariant ge rs m ->
          AsmX.asm_invariant ge rs' m'.
      Proof.
        unfold exec_storeex1. intros until m'.
        destruct (eval_addrmode ge adr rs); try discriminate.
        * destruct (ihost (snd m)); try discriminate.
          destruct (pg (snd m)); try discriminate.
        + eapply exec_host_store1_asm_invariant; eauto.
        + intros; eapply exec_guest_intel_store1_asm_invariant; eauto.
          * destruct (ikern (snd m)); try discriminate.
            destruct (ihost (snd m)); try discriminate.
            intros; eapply exec_store_invariant; eauto.
      Qed.

      Lemma exec_storeex1_low_level_invariant:
        forall adr chunk m rs rd des rs' m',
          exec_storeex1 chunk m adr rs rd des = Next rs' m' ->
          AsmX.asm_invariant ge rs m ->
          CompatData.low_level_invariant (Mem.nextblock m) (snd m) ->
          CompatData.low_level_invariant (Mem.nextblock m') (snd m').
      Proof.
        unfold exec_storeex1. intros until m'.
        destruct (eval_addrmode ge adr rs); try discriminate.
        * destruct (ihost (snd m)); try discriminate.
          destruct (pg (snd m)); try discriminate.
        + eapply exec_host_store1_low_level_invariant; eauto.
        + intros; eapply exec_guest_intel_store1_low_level_invariant; eauto.
          * destruct (ikern (snd m)); try discriminate.
            destruct (ihost (snd m)); try discriminate.
            unfold Asm.exec_store. destruct (Mem.storev chunk m (eval_addrmode ge adr rs) (rs rd)) eqn:Heqo; 
                                   try discriminate.
            destruct (eval_addrmode ge adr rs); try discriminate.
            lift_unfold.
            destruct Heqo as [? DATA].
            unfold π_data in DATA. simpl in * |- *.
            injection 1; intros; subst.
            erewrite Mem.nextblock_store; eauto.
            congruence.
      Qed.

  End GE.      

  Context `{KernelModeImplies (Obs:=Obs) (data_ops:= data_ops)}.
  Context {flat_inv: FlatmemStoreInvariant (data_ops := data_ops) (flatmem_store:= flatmem_store)}.
  
  Global Instance load_accessor_prf1:
    LoadAccessor _ (@exec_loadex1).
  Proof.
    constructor.
    {
      unfold exec_loadex1.
      intros.
      erewrite AsmX.eval_addrmode_symbols_preserved; eauto.
      destruct (eval_addrmode ge1 a rs); try reflexivity.
      - destruct (ihost (snd m)); try reflexivity.
        destruct (pg (snd m)); try reflexivity.
        + unfold exec_host_load1.
          destruct (CR3 (snd m)); try reflexivity.
          (*unfold exec_host_load_snd0.*)
          unfold exec_pagefault. repeat rewrite SYMB.
          destruct (Genv.find_symbol ge1 b); try reflexivity.
        (*destruct (Mem.loadv Mint32 m
                            (Vptr b0 (Int.repr (Int.unsigned ofs + PDX (Int.unsigned i) * 4)))); try reflexivity.
        destruct v; try reflexivity.
        destruct (Mem.loadv Mint32 m
                            (Vptr b1
                                  (Int.repr
                                     (Int.unsigned i0 / 4096 * 4096 + PTX (Int.unsigned i) * 4)))); try reflexivity.
        destruct v; try reflexivity.
        unfold Asm.exec_load. 
        erewrite AsmX.eval_addrmode_symbols_preserved; eauto.*)
        + eapply exec_guest_intel_accessor1_eq; eauto.
      - unfold Asm.exec_load. 
        erewrite AsmX.eval_addrmode_symbols_preserved; eauto.
    }
    {
      intros. apply kernel_mode_implies in H1.
      destruct H1 as [IKERN IHOST].
      unfold exec_loadex1.
      unfold Asm.exec_load in H0 |- *.
      destruct (eval_addrmode ge a rs); try discriminate.
      unfold π_data in IKERN, IHOST.
      rewrite IKERN. rewrite IHOST.
      assumption.
    }
    {
      intros; eapply exec_loadex1_asm_invariant; eauto.
    }     
    {
      intros; eapply exec_loadex1_low_level_invariant; eauto.
    }
    {
      intros; eapply exec_loadex1_high_level_invariant; eauto.
    }
  Qed.

  Global Instance store_accessor_prf1:
    StoreAccessor _ (@exec_storeex1).
  Proof.
    constructor.
    {
      unfold exec_storeex1.
      intros.
      erewrite AsmX.eval_addrmode_symbols_preserved; eauto.
      destruct (eval_addrmode ge1 a rs); try reflexivity.
      - destruct (ihost (snd m)); try reflexivity.
        destruct (pg (snd m)); try reflexivity.
        + unfold exec_host_store1.
          destruct (CR3 (snd m)); try reflexivity.
          (*unfold exec_host_store_snd0.*)
          unfold exec_pagefault. repeat rewrite SYMB. 
          destruct (Genv.find_symbol ge1 b); try reflexivity.
        (*destruct (Mem.loadv Mint32 m
                            (Vptr b0 (Int.repr (Int.unsigned ofs + PDX (Int.unsigned i) * 4)))); try reflexivity.
        destruct v; try reflexivity.        
        destruct (Mem.loadv Mint32 m
                            (Vptr b1
                                  (Int.repr
                                     (Int.unsigned i0 / 4096 * 4096 + PTX (Int.unsigned i) * 4)))); try reflexivity.
        destruct v; try reflexivity.
        unfold Asm.exec_store. 
        erewrite AsmX.eval_addrmode_symbols_preserved; eauto.*)
        + eapply exec_guest_intel_accessor1_eq; eauto.
      - unfold Asm.exec_store. erewrite AsmX.eval_addrmode_symbols_preserved; eauto.
    }
    {
      intros. apply kernel_mode_implies in H1.
      destruct H1 as [IKERN IHOST].
      unfold exec_storeex1.
      unfold Asm.exec_store in H0 |- *.
      destruct (eval_addrmode ge a rs); try discriminate.
      unfold π_data in IKERN, IHOST.
      rewrite IKERN. rewrite IHOST.
      assumption.
    }
    {
      intros; eapply exec_storeex1_asm_invariant; eauto.
    }     
    {
      intros; eapply exec_storeex1_low_level_invariant; eauto.
    }
    {
      intros; eapply exec_storeex1_high_level_invariant; eauto.
    }
  Qed.

End Load_Store.

Require Import LoadStoreGeneral.

Section Load_Store_Refinement.

  Context `{Hobs: Observation}.
  Context `{Hmem: Mem.MemoryModel}.
  Context `{Hmwd: UseMemWithData mem}.
  Context `{HD: CompatData(Obs:=Obs) RData}.
  Context `{HD0: CompatData(Obs:=Obs) RData}.

  Notation HDATAOps := (cdata (cdata_ops := data_ops) RData).
  Notation LDATAOps := (cdata (cdata_ops := data_ops0) RData).
  Context `{rel_prf: CompatRel (Obs:=Obs) (mem:=mem) (memory_model_ops:= memory_model_ops) (D1 := HDATAOps) (D2:=LDATAOps)}. 
  Context `{Hstencil: Stencil stencil (stencil_ops:= stencil_ops)}.
  Context `{trapinfo_inv: TrapinfoSetInvariant (Obs:=Obs) (data_ops:= data_ops)}.
  Context `{kern_inv: KernelModeImplies (Obs:=Obs) (data_ops:= data_ops)}.

  Context `{hflatmem_store: RData -> memory_chunk -> Z -> val -> option RData}.
  Context `{lflatmem_store: RData -> memory_chunk -> Z -> val -> option RData}.
  
  Section Load_Store1.

    Context {loadstoreprop: LoadStoreProp (hflatmem_store:= hflatmem_store) (lflatmem_store:= lflatmem_store)}.
    Context {re: relate_impl_CR3}.
    Context {re1: relate_impl_HP'}.
    Context {re2: relate_impl_iflags}.

    Notation hLoad := (fun F V => exec_loadex1 (F:=F) (V:=V)).
    Notation lLoad := (fun F V => exec_loadex1 (F:=F) (V:=V)).
    Notation hStore := (fun F V => exec_storeex1 (F:=F) (V:=V) (flatmem_store:= hflatmem_store)).
    Notation lStore := (fun F V => exec_storeex1 (F:=F) (V:=V) (flatmem_store:= lflatmem_store)).

    Opaque align_chunk Z.mul Z.div Z.sub. 

    Lemma load_correct1:
      load_accessor_sim_def HDATAOps LDATAOps (one_crel HDATAOps LDATAOps) hLoad lLoad.
    Proof.      
      unfold load_accessor_sim_def. intros.
      pose proof H2 as Hmatch.
      inv H2. inv match_extcall_states.
      exploit relate_impl_iflags_eq; eauto. inversion 1.
      pose proof (stencil_matches_preserves_trans _ _ _ _ _ _ _ H0 H) as Hpre.            
      erewrite exec_load_symbols_preserved in H1; try eapply Hpre.
      unfold exec_loadex1 in *; simpl in *.
      rewrite <- ihost_eq, <- ikern_eq, <- pg_eq.
      exploit (eval_addrmode_correct ge2 ge2 a); eauto. simpl; intros HW.
      destruct (eval_addrmode ge2 a rs1) eqn: HVAL; contra_inv.
      inv HW.
      simpl in *; subdestruct.
      - eapply host_load_correct1; eauto.
      - eapply guest_intel_load_correct1; eauto.
      - inv HW; simpl in *.
        subdestruct.
        eapply loadl_correct; eauto.
    Qed.

    Lemma store_correct1:
      store_accessor_sim_def HDATAOps LDATAOps (one_crel HDATAOps LDATAOps) hStore lStore.
    Proof.
      unfold store_accessor_sim_def. intros.
      pose proof H2 as Hmatch.
      inv H2. inv match_extcall_states.
      exploit relate_impl_iflags_eq; eauto. inversion 1.
      pose proof (stencil_matches_preserves_trans _ _ _ _ _ _ _ H0 H) as Hpre.
      unfold exec_storeex1 in *.
      simpl in *. rewrite <- ihost_eq, <- ikern_eq, <- pg_eq.
      exploit (eval_addrmode_correct ge1 ge2 a); eauto. simpl; intros HW.
      destruct (eval_addrmode ge1 a rs1) eqn: HVAL; contra_inv.
      inv HW.
      simpl in *; subdestruct.
      - eapply host_store_correct1; eauto.
      - eapply guest_intel_store_correct1; eauto.
      - inv HW; simpl in *.
        subdestruct.
        eapply storel_correct; eauto.
    Qed.

  End Load_Store1.

End Load_Store_Refinement.