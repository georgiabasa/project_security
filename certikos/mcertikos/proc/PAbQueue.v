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
(*              Layers of PM: PAbQueue                                 *)
(*                                                                     *)
(*          Provide initialization of thread queue                     *)
(*                                                                     *)
(*          Ronghui Gu <ronghui.gu@yale.edu>                           *)
(*          Yu Guo <yu.guo@yale.edu>                                   *)
(*                                                                     *)
(*          Yale Flint Group                                           *)
(*                                                                     *)
(* *********************************************************************)

(** This file defines the abstract data and the primitives for the PAbQueue layer, 
which will introduce abstraction of kernel context*)
Require Import Coqlib.
Require Import Maps.
Require Import ASTExtra.
Require Import Integers.
Require Import Floats.
Require Import Values.
Require Import Memory.
Require Import Events.
Require Import Stacklayout.
Require Import Globalenvs.
Require Import AsmX.
Require Import Smallstep.
Require Import AuxStateDataType.
Require Import Constant.
Require Import GlobIdent.
Require Import FlatMemory.
Require Import CommonTactic.
Require Import AuxLemma.
Require Import RealParams.
Require Import PrimSemantics.
Require Import LAsm.
Require Import LoadStoreSem2.
Require Import XOmega.
Require Import ObservationImpl.

Require Import liblayers.logic.PTreeModules.
Require Import liblayers.logic.LayerLogicImpl.
Require Import liblayers.compat.CompatLayers.
Require Import liblayers.compat.CompatGenSem.

Require Import CalRealPTPool.
Require Import CalRealPT.
Require Import CalRealIDPDE.
Require Import CalRealInitPTE.
Require Import CalRealSMSPool.
Require Import CalRealProcModule.

Require Import INVLemmaContainer.
Require Import INVLemmaMemory.
Require Import INVLemmaThread.

Require Import AbstractDataType.

Require Export ObjCPU.
Require Export ObjFlatMem.
Require Export ObjContainer.
Require Export ObjVMM.
Require Export ObjLMM.
Require Export ObjShareMem.
Require Export ObjThread.

(** * Abstract Data and Primitives at this layer*)
Section WITHMEM.

  Local Open Scope Z_scope.

  Context `{real_params: RealParams}.

  (** **Definition of the raw data at MPTBit layer*)
  (*Record RData :=
    mkRData {
        HP: flatmem; (**r we model the memory from 1G to 3G as heap*)
        ti: trapinfo; (**r abstract of CR2, stores the address where page fault happens*)
        pe: bool; (**r abstract of CR0, indicates whether the paging is enabled or not*)
        ikern: bool; (**r pure logic flag, shows whether it's in kernel mode or not*)
        ihost: bool; (**r logic flag, shows whether it's in the host mode or not*)         
        AT: ATable; (**r allocation table*)
        nps: Z; (**r number of the pages*)

        PT: Z; (**r the current page table index*)
        ptpool: PTPool; (**r page table pool*)
        ipt: bool; (**r pure logic flag, shows whether it's using the kernel's page table*)
        pb : PTBitMap; (**r [page table bit map], indicating which page table has been used*)

        kctxt: KContextPool; (**r kernel context pool*)
        abtcb: AbTCBPool; (**r thread control blocks pool*)
        abq: AbQueuePool (**r thread queue pool*)
      }.*)

  (** **Definition of the invariants at MPTNew layer*)
  (** [0th page map] is reserved for the kernel thread*)
  Record high_level_invariant (abd: RData) :=
    mkInvariant {
        valid_nps: pg abd = true -> kern_low <= nps abd <= maxpage;
        valid_AT_kern: pg abd = true -> LAT_kern (LAT abd) (nps abd);
        valid_AT_usr: pg abd = true -> LAT_usr (LAT abd) (nps abd);
        valid_kern: ipt abd = false -> pg abd = true;
        valid_iptt: ipt abd = true -> ikern abd = true; 
        valid_iptf: ikern abd = false -> ipt abd = false; 
        valid_ihost: ihost abd = false -> pg abd = true /\ ikern abd = true;
        valid_container: Container_valid (AC abd);
        valid_pperm_ppage: Lconsistent_ppage (LAT abd) (pperm abd) (nps abd);
        init_pperm: pg abd = false -> (pperm abd) = ZMap.init PGUndef;
        valid_PMap: pg abd = true -> 
                    (forall i, 0<= i < num_proc ->
                               PMap_valid (ZMap.get i (ptpool abd)));
        (* 0th page map is reserved for the kernel thread*)          
        valid_PT_kern: pg abd = true -> ipt abd = true -> (PT abd) = 0;
        valid_PMap_kern: pg abd = true -> PMap_kern (ZMap.get 0 (ptpool abd));
        valid_PT: pg abd = true -> 0<= PT abd < num_proc;
        valid_dirty: dirty_ppage (pperm abd) (HP abd);

        valid_idpde: pg abd = true -> IDPDE_init (idpde abd);
        valid_pperm_pmap: consistent_pmap (ptpool abd) (pperm abd) (LAT abd) (nps abd);
        valid_pmap_domain: consistent_pmap_domain (ptpool abd) (pperm abd) (LAT abd) (nps abd);
        valid_lat_domain: consistent_lat_domain (ptpool abd) (LAT abd) (nps abd);

        valid_root: pg abd = true -> cused (ZMap.get 0 (AC abd)) = true;

        valid_TCB: pg abd = true -> AbTCBCorrect_range (abtcb abd);
        valid_TDQ: pg abd = true -> AbQCorrect_range (abq abd);
        valid_notinQ: pg abd = true -> NotInQ (AC abd) (abtcb abd);
        valid_count: pg abd = true -> QCount (abtcb abd) (abq abd);
        valid_inQ: pg abd = true -> InQ (abtcb abd) (abq abd)

      }.

  (** ** Definition of the abstract state ops *)
  Global Instance pabqueue_data_ops : CompatDataOps RData :=
    {
      empty_data := init_adt;
      high_level_invariant := high_level_invariant;
      low_level_invariant := low_level_invariant;
      kernel_mode adt := ikern adt = true /\ ihost adt = true;
      observe := ObservationImpl.observe
    }.

  (** ** Proofs that the initial abstract_data should satisfy the invariants*)    
  Section Property_Abstract_Data.

    Lemma empty_data_high_level_invariant:
      high_level_invariant init_adt.
    Proof.
      constructor; simpl; intros; auto; try inv H.
      - apply empty_container_valid.
      - eapply Lconsistent_ppage_init.
      - eapply dirty_ppage_init.
      - eapply consistent_pmap_init.
      - eapply consistent_pmap_domain_init.
      - eapply consistent_lat_domain_init.
   Qed.

    (** ** Definition of the abstract state *)
    Global Instance pabqueue_data_prf : CompatData RData.
    Proof.
      constructor.
      - apply low_level_invariant_incr.
      - apply empty_data_low_level_invariant.
      - apply empty_data_high_level_invariant.
    Qed.

  End Property_Abstract_Data.

  Context `{Hstencil: Stencil}.
  Context `{Hmem: Mem.MemoryModel}.
  Context `{Hmwd: UseMemWithData mem}.

  (** * Proofs that the primitives satisfies the invariants at this layer *)
  Section INV.

    Section ALLOC.
      
      Lemma alloc_high_level_inv:
        forall d d' i n,
          alloc_spec i d = Some (d', n) ->
          high_level_invariant d ->
          high_level_invariant d'.
      Proof.
        intros. functional inversion H; subst; eauto. 
        inv H0. constructor; simpl; eauto.
        - intros; eapply LAT_kern_norm; eauto. eapply _x.
        - intros; eapply LAT_usr_norm; eauto.
        - eapply alloc_container_valid'; eauto.
        - eapply Lconsistent_ppage_norm_alloc; eauto.
        - intros; congruence.
        - eapply dirty_ppage_gso_alloc; eauto.
        - eapply consistent_pmap_gso_at_false; eauto. apply _x.
        - eapply consistent_pmap_domain_gso_at_false; eauto. apply _x.
        - eapply consistent_lat_domain_gss_nil; eauto.
        - zmap_solve.
        - intros; apply NotInQ_gso_true; auto.
      Qed.
      
      Lemma alloc_low_level_inv:
        forall d d' i n n',
          alloc_spec i d = Some (d', n) ->
          low_level_invariant n' d ->
          low_level_invariant n' d'.
      Proof.
        intros. functional inversion H; subst; eauto.
        inv H0. constructor; eauto.
      Qed.

      Lemma alloc_kernel_mode:
        forall d d' i n,
          alloc_spec i d = Some (d', n) ->
          kernel_mode d ->
          kernel_mode d'.
      Proof.
        intros. functional inversion H; subst; eauto.
      Qed.

      Global Instance alloc_inv: PreservesInvariants alloc_spec.
      Proof.
        preserves_invariants_simpl'.
        - eapply alloc_low_level_inv; eassumption.
        - eapply alloc_high_level_inv; eassumption.
        - eapply alloc_kernel_mode; eassumption.
      Qed.

    End ALLOC.

    Global Instance pfree_inv: PreservesInvariants pfree_spec.
    Proof.
      preserves_invariants_simpl low_level_invariant high_level_invariant; eauto 2.
      - intros; eapply LAT_kern_norm; eauto. 
      - intros; eapply LAT_usr_norm; eauto.
      - eapply Lconsistent_ppage_norm_undef; eauto.
      - eapply dirty_ppage_gso_undef; eauto.
      - eapply consistent_pmap_gso_pperm_alloc; eauto.
      - eapply consistent_pmap_domain_gso_at_0; eauto.
      - eapply consistent_lat_domain_gss_nil; eauto.
    Qed.

    Global Instance trapin_inv: PrimInvariants trapin_spec.
    Proof.
      PrimInvariants_simpl H H0.
    Qed.

    Global Instance trapout_inv: PrimInvariants trapout_spec.
    Proof.
      PrimInvariants_simpl H H0.
    Qed.

    Global Instance hostin_inv: PrimInvariants hostin_spec.
    Proof.
      PrimInvariants_simpl H H0.
    Qed.

    Global Instance hostout_inv: PrimInvariants hostout_spec.
    Proof.
      PrimInvariants_simpl H H0.
    Qed.

    Global Instance ptin_inv: PrimInvariants ptin_spec.
    Proof.
      PrimInvariants_simpl H H0.
    Qed.

    Global Instance ptout_inv: PrimInvariants ptout_spec.
    Proof.
      PrimInvariants_simpl H H0.
    Qed.

    Global Instance fstore_inv: PreservesInvariants fstore_spec.
    Proof.
      split; intros; inv_generic_sem H; inv H0; functional inversion H2.
      - functional inversion H. split; trivial.        
      - functional inversion H.
        split; subst; simpl; 
        try (eapply dirty_ppage_store_unmaped; try reflexivity; try eassumption); trivial. 
      - functional inversion H0.
        split; simpl; try assumption.
    Qed.

    Global Instance setPT_inv: PreservesInvariants setPT_spec.
    Proof.
      preserves_invariants_simpl low_level_invariant high_level_invariant; eauto 2.
    Qed.

    Section PTINSERT.
      
      Section PTINSERT_PTE.

        Lemma ptInsertPTE_high_level_inv:
          forall d d' n vadr padr p,
            ptInsertPTE0_spec n vadr padr p d = Some d' ->
            high_level_invariant d ->
            high_level_invariant d'.
        Proof.
          intros. functional inversion H; subst; eauto.
          inv H0; constructor_gso_simpl_tac; intros.
          - eapply LAT_kern_norm; eauto. 
          - eapply LAT_usr_norm; eauto.
          - eapply Lconsistent_ppage_norm; eassumption.
          - eapply PMap_valid_gso_valid; eauto.
          - functional inversion H2. functional inversion H1. 
            eapply PMap_kern_gso; eauto.
          - functional inversion H2. functional inversion H0.
            eapply consistent_pmap_ptp_same; try eassumption.
            eapply consistent_pmap_gso_pperm_alloc'; eassumption.
          - functional inversion H2.
            eapply consistent_pmap_domain_append; eauto.
            destruct (ZMap.get pti pdt); try contradiction;
            red; intros (v0 & p0 & He); contra_inv. 
          - eapply consistent_lat_domain_gss_append; eauto.
            subst pti; destruct (ZMap.get (PTX vadr) pdt); try contradiction;
            red; intros (v0 & p0 & He); contra_inv. 
        Qed.

        Lemma ptInsertPTE_low_level_inv:
          forall d d' n vadr padr p n',
            ptInsertPTE0_spec n vadr padr p d = Some d' ->
            low_level_invariant n' d ->
            low_level_invariant n' d'.
        Proof.
          intros. functional inversion H; subst; eauto.
          inv H0. constructor; eauto.
        Qed.

        Lemma ptInsertPTE_kernel_mode:
          forall d d' n vadr padr p,
            ptInsertPTE0_spec n vadr padr p d = Some d' ->
            kernel_mode d ->
            kernel_mode d'.
        Proof.
          intros. functional inversion H; subst; eauto.
        Qed.

      End PTINSERT_PTE.

      Section PTALLOCPDE.

        Lemma ptAllocPDE_high_level_inv:
          forall d d' n vadr v,
            ptAllocPDE0_spec n vadr d = Some (d', v) ->
            high_level_invariant d ->
            high_level_invariant d'.
        Proof.
          intros. functional inversion H; subst; eauto. 
          inv H0; constructor_gso_simpl_tac; intros.
          - eapply LAT_kern_norm; eauto. eapply _x.
          - eapply LAT_usr_norm; eauto.
          - eapply alloc_container_valid'; eauto.
          - apply Lconsistent_ppage_norm_hide; try assumption.
          - congruence.
          - eapply PMap_valid_gso_pde_unp; eauto.
            eapply real_init_PTE_defined.
          - functional inversion H3. 
            eapply PMap_kern_gso; eauto.
          - eapply dirty_ppage_gss; eauto.
          - eapply consistent_pmap_ptp_gss; eauto; apply _x.
          - eapply consistent_pmap_domain_gso_at_false; eauto; try apply _x.
            eapply consistent_pmap_domain_ptp_unp; eauto.
            apply real_init_PTE_unp.
          - apply consistent_lat_domain_gss_nil; eauto.
            apply consistent_lat_domain_gso_p; eauto.
          - zmap_solve.
          - apply NotInQ_gso_true; auto.
        Qed.

        Lemma ptAllocPDE_low_level_inv:
          forall d d' n vadr v n',
            ptAllocPDE0_spec n vadr d = Some (d', v) ->
            low_level_invariant n' d ->
            low_level_invariant n' d'.
        Proof.
          intros. functional inversion H; subst; eauto.
          inv H0. constructor; eauto.
        Qed.

        Lemma ptAllocPDE_kernel_mode:
          forall d d' n vadr v,
            ptAllocPDE0_spec n vadr d = Some (d', v) ->
            kernel_mode d ->
            kernel_mode d'.
        Proof.
          intros. functional inversion H; subst; eauto.
        Qed.

      End PTALLOCPDE.

      Lemma ptInsert_high_level_inv:
        forall d d' n vadr padr p v,
          ptInsert0_spec n vadr padr p d = Some (d', v) ->
          high_level_invariant d ->
          high_level_invariant d'.
      Proof.
        intros. functional inversion H; subst; eauto. 
        - eapply ptInsertPTE_high_level_inv; eassumption.
        - eapply ptAllocPDE_high_level_inv; eassumption.
        - eapply ptInsertPTE_high_level_inv; try eassumption.
          eapply ptAllocPDE_high_level_inv; eassumption.
      Qed.

      Lemma ptInsert_low_level_inv:
        forall d d' n vadr padr p n' v,
          ptInsert0_spec n vadr padr p d = Some (d', v) ->
          low_level_invariant n' d ->
          low_level_invariant n' d'.
      Proof.
        intros. functional inversion H; subst; eauto.
        - eapply ptInsertPTE_low_level_inv; eassumption.
        - eapply ptAllocPDE_low_level_inv; eassumption.
        - eapply ptInsertPTE_low_level_inv; try eassumption.
          eapply ptAllocPDE_low_level_inv; eassumption.
      Qed.

      Lemma ptInsert_kernel_mode:
        forall d d' n vadr padr p v,
          ptInsert0_spec n vadr padr p d = Some (d', v) ->
          kernel_mode d ->
          kernel_mode d'.
      Proof.
        intros. functional inversion H; subst; eauto.
        - eapply ptInsertPTE_kernel_mode; eassumption.
        - eapply ptAllocPDE_kernel_mode; eassumption.
        - eapply ptInsertPTE_kernel_mode; try eassumption.
          eapply ptAllocPDE_kernel_mode; eassumption.
      Qed.

    End PTINSERT.

    Section PTRESV.

      Lemma ptResv_high_level_inv:
        forall d d' n vadr p v,
          ptResv_spec n vadr p d = Some (d', v) ->
          high_level_invariant d ->
          high_level_invariant d'.
      Proof.
        intros. functional inversion H; subst; eauto. 
        eapply ptInsert_high_level_inv; try eassumption.
        eapply alloc_high_level_inv; eassumption.
      Qed.

      Lemma ptResv_low_level_inv:
        forall d d' n vadr p n' v,
          ptResv_spec n vadr p d = Some (d', v) ->
          low_level_invariant n' d ->
          low_level_invariant n' d'.
      Proof.
        intros. functional inversion H; subst; eauto.
        eapply ptInsert_low_level_inv; try eassumption.
        eapply alloc_low_level_inv; eassumption.
      Qed.

      Lemma ptResv_kernel_mode:
        forall d d' n vadr p v,
          ptResv_spec n vadr p d = Some (d', v) ->
          kernel_mode d ->
          kernel_mode d'.
      Proof.
        intros. functional inversion H; subst; eauto.
        eapply ptInsert_kernel_mode; try eassumption.
        eapply alloc_kernel_mode; eassumption.
      Qed.

      Global Instance ptResv_inv: PreservesInvariants ptResv_spec.
      Proof.
        preserves_invariants_simpl'.
        - eapply ptResv_low_level_inv; eassumption.
        - eapply ptResv_high_level_inv; eassumption.
        - eapply ptResv_kernel_mode; eassumption.
      Qed.

    End PTRESV.

    Section OFFER_SHARE.

      Section PTRESV2.

        Lemma ptResv2_high_level_inv:
          forall d d' n vadr p n' vadr' p' v,
            ptResv2_spec n vadr p n' vadr' p' d = Some (d', v) ->
            high_level_invariant d ->
            high_level_invariant d'.
        Proof.
          intros; functional inversion H; subst; eauto;
          eapply ptInsert_high_level_inv; try eassumption.
          - eapply alloc_high_level_inv; eassumption.
          - eapply ptInsert_high_level_inv; try eassumption.
            eapply alloc_high_level_inv; eassumption.
        Qed.

        Lemma ptResv2_low_level_inv:
          forall d d' n vadr p n' vadr' p' l v,
            ptResv2_spec n vadr p n' vadr' p' d = Some (d', v) ->
            low_level_invariant l d ->
            low_level_invariant l d'.
        Proof.
          intros; functional inversion H; subst; eauto;
          eapply ptInsert_low_level_inv; try eassumption.
          - eapply alloc_low_level_inv; eassumption.
          - eapply ptInsert_low_level_inv; try eassumption.
            eapply alloc_low_level_inv; eassumption.
        Qed.

        Lemma ptResv2_kernel_mode:
          forall d d' n vadr p n' vadr' p' v,
            ptResv2_spec n vadr p n' vadr' p' d = Some (d', v) ->
            kernel_mode d ->
            kernel_mode d'.
        Proof.
          intros; functional inversion H; subst; eauto;
          eapply ptInsert_kernel_mode; try eassumption.
          - eapply alloc_kernel_mode; eassumption.
          - eapply ptInsert_kernel_mode; try eassumption.
            eapply alloc_kernel_mode; eassumption.
        Qed.

      End PTRESV2.

      Global Instance offer_shared_mem_inv: 
        PreservesInvariants offer_shared_mem_spec.
      Proof.
        preserves_invariants_simpl';
        functional inversion H2; subst; eauto 2; try (inv H0; constructor; trivial; fail).
        - exploit ptResv2_low_level_inv; eauto.
          intros HP; inv HP. constructor; trivial.
        - exploit ptResv2_low_level_inv; eauto.
          intros HP; inv HP. constructor; trivial.
        - exploit ptResv2_high_level_inv; eauto.
          intros HP; inv HP. constructor; trivial.
        - exploit ptResv2_high_level_inv; eauto.
          intros HP; inv HP. constructor; trivial.
        - exploit ptResv2_kernel_mode; eauto.
        - exploit ptResv2_kernel_mode; eauto.
      Qed.

    End OFFER_SHARE.

    Global Instance shared_mem_status_inv: 
      PreservesInvariants shared_mem_status_spec.
    Proof.
      preserves_invariants_simpl low_level_invariant high_level_invariant; eauto 2.
    Qed.

    Global Instance kctxt_switch_inv: KCtxtSwitchInvariants kctxt_switch_spec.
    Proof.
      constructor; intros; functional inversion H. 
      - inv H1. constructor; trivial. 
        eapply kctxt_inject_neutral_gss_mem; eauto.
      - inv H0. subst. constructor; auto; simpl in *; intros; try congruence.
    Qed.
       
    Global Instance kctxt_new_inv: DNewInvariants kctxt_new_spec.
    Proof.
      constructor; intros; inv H0;
      unfold ObjThread.kctxt_new_spec in *;
      subdestruct; inv H; simpl; auto.
      - (* low level invariant *)
        constructor; trivial; intros; simpl in *.
        eapply kctxt_inject_neutral_gss_flatinj'; eauto.
        eapply kctxt_inject_neutral_gss_flatinj; eauto.

      - (* high_level_invariant *)
        constructor; simpl; eauto 2; try congruence; intros.
        + exploit split_container_valid; eauto.
          eapply container_split_some; eauto.
          auto.
        + unfold update_cusage, update_cchildren; zmap_solve.
        + unfold update_cusage, update_cchildren; apply NotInQ_gso_true; auto.
          zmap_simpl; repeat apply NotInQ_gso_true; auto.
    Qed.

    Global Instance set_state_inv: PreservesInvariants set_state0_spec.
    Proof.
      preserves_invariants_simpl low_level_invariant high_level_invariant; auto 2.
      - eapply AbTCBCorrect_range_gss; eauto.
        eapply AbTCBCorrect_range_valid_b; eauto.
      - eapply NotInQ_gso_state; eauto.
      - eapply QCount_gso_state; eauto.
      - eapply InQ_gso_state; eauto.
    Qed.

    Global Instance tdqueue_init_inv: PreservesInvariants tdqueue_init0_spec.
    Proof.
      preserves_invariants_simpl low_level_invariant high_level_invariant.
      - apply real_nps_range.
      - apply real_lat_kern_valid.
      - apply real_lat_usr_valid.
      - apply real_container_valid.
      - rewrite init_pperm0; try assumption.
        apply Lreal_pperm_valid.        
      - eapply real_pt_PMap_valid; eauto.
      - apply real_pt_PMap_kern.
      - omega.
      - assumption.
      - apply real_idpde_init.
      - apply real_pt_consistent_pmap. 
      - apply real_pt_consistent_pmap_domain. 
      - apply Lreal_at_consistent_lat_domain.
      - apply real_abtcb_range; auto.
      - apply real_abq_range; auto.
      - eapply real_abtcb_pb_notInQ; eauto.
      - eapply real_abtcb_abq_QCount; eauto.
      - eapply real_abq_tcb_inQ; eauto.
    Qed.

    Global Instance enqueue_inv: PreservesInvariants enqueue0_spec.
    Proof.
      preserves_invariants_simpl low_level_invariant high_level_invariant; eauto 2;
      functional inversion H5.
      - eapply AbTCBCorrect_range_gss; eauto. omega.
      - eapply AbQCorrect_range_gss_enqueue; eauto.
      - eapply NotInQ_gso_ac; eauto.
      - eapply QCount_gss_enqueue; eauto. 
      - eapply InQ_gss_enqueue; eauto.
    Qed.

    Global Instance dequeue_inv: PreservesInvariants dequeue0_spec.
    Proof.
      preserves_invariants_simpl low_level_invariant high_level_invariant; eauto 2.
      - eapply AbTCBCorrect_range_gss; eauto. omega.
      - eapply AbQCorrect_range_gss_remove; eauto.
      - eapply NotInQ_gso_neg; eauto.
      - eapply QCount_gss_remove; eauto.
        eapply last_range_AbQ; eauto.
      - eapply InQ_gss_remove; eauto.
        + eapply last_range_AbQ; eauto.
        + apply last_correct; auto.
    Qed.

    Global Instance queue_rmv_inv: PreservesInvariants queue_rmv0_spec.
    Proof.
      preserves_invariants_simpl low_level_invariant high_level_invariant; eauto 2;
      functional inversion H5.
      - eapply AbTCBCorrect_range_gss; eauto. omega.
      - eapply AbQCorrect_range_gss_remove; eauto.
      - eapply NotInQ_gso_neg; eauto.
      - eapply QCount_gss_remove; eauto.
      - eapply InQ_gss_remove; eauto.
        eapply QCount_valid; eauto.
    Qed.

    Global Instance clearCR2_inv: PreservesInvariants clearCR2_spec.
    Proof.
      preserves_invariants_simpl low_level_invariant high_level_invariant; auto.
    Qed.

    (*Global Instance thread_free_inv: PreservesInvariants thread_free_spec.
    Proof.
      preserves_invariants_simpl low_level_invariant high_level_invariant; eauto 2.
      - destruct (zeq i0 (Int.unsigned i)); subst.
        + rewrite ZMap.gss. apply PT_init_common_pdt_usr.
          apply real_free_pt_valid; apply valid_PT_common0; auto.
        + rewrite ZMap.gso; auto.
      - destruct (zeq (Int.unsigned i) 0); subst. omega.
        rewrite ZMap.gso; auto.
      - destruct (zeq (Int.unsigned i) 0); subst. omega.
        rewrite ZMap.gso; auto.
      - unfold PTB_defined in *; intros.
        destruct (zeq (Int.unsigned i) i0); subst.
        rewrite ZMap.gss.
        red; intros HF; inv HF.
        rewrite ZMap.gso; auto.
      - destruct (zeq (Int.unsigned i) i0); subst.
        + rewrite ZMap.gss. unfold AbTCBCorrect in *.
          refine_split'; eauto; omega.
        + rewrite ZMap.gso; auto.
      - destruct (zeq (Int.unsigned i) i0); subst.
        + rewrite ZMap.gss in *. inv H12; trivial.
        + rewrite ZMap.gso in *; eauto.
      - destruct (zeq (Int.unsigned i) i0); subst.
        + rewrite ZMap.gss in *. inv H11. eauto.
        + rewrite ZMap.gso in *; eauto.
      - destruct (zeq (Int.unsigned i) i0); subst.
        + rewrite ZMap.gss.
          destruct (valid_inQ0 H4 _ _ _ H10 H11 H12 H13) as [s' HM].
          rewrite H8 in HM. inv HM. omega.
        + rewrite ZMap.gso; eauto.      
    Qed.*)

    Global Instance flatmem_copy_inv: PreservesInvariants flatmem_copy_spec.
    Proof.
      preserves_invariants_simpl low_level_invariant high_level_invariant;      
      try eapply dirty_ppage_gss_copy; eauto.
    Qed.

    Global Instance device_output_inv: PreservesInvariants device_output_spec.
    Proof. 
      preserves_invariants_simpl'' low_level_invariant high_level_invariant; eauto.
    Qed.

  End INV.

  Definition exec_loadex {F V} := exec_loadex2 (F := F) (V := V).

  Definition exec_storeex {F V} :=  exec_storeex2 (flatmem_store:= flatmem_store) (F := F) (V := V).

  Global Instance flatmem_store_inv: FlatmemStoreInvariant (flatmem_store:= flatmem_store).
  Proof.
    split; inversion 1; intros. 
    - functional inversion H0. split; trivial.
    - functional inversion H1. 
      split; simpl; try (eapply dirty_ppage_store_unmaped'; try reflexivity; try eassumption); trivial.
  Qed.

  Global Instance trapinfo_set_inv: TrapinfoSetInvariant.
  Proof.
    split; inversion 1; intros; constructor; auto.
  Qed.

  (** * Layer Definition *)
  Definition pabqueue : compatlayer (cdata RData) :=
    fload ↦ gensem fload_spec
          ⊕ fstore ↦ gensem fstore_spec
          ⊕ flatmem_copy ↦ gensem flatmem_copy_spec
          ⊕ vmxinfo_get ↦ gensem vmxinfo_get_spec
          ⊕ device_output ↦ gensem device_output_spec
          ⊕ pfree ↦ gensem pfree_spec
          ⊕ set_pt ↦ gensem setPT_spec
          ⊕ pt_read ↦ gensem ptRead_spec
          ⊕ pt_resv ↦ gensem ptResv_spec
          ⊕ kctxt_new ↦ dnew_compatsem ObjThread.kctxt_new_spec
          (*⊕ pt_free ↦ gensem pt_free_spec*)
          ⊕ shared_mem_status ↦ gensem shared_mem_status_spec
          ⊕ offer_shared_mem ↦ gensem offer_shared_mem_spec

          ⊕ get_state ↦ gensem get_state0_spec
          ⊕ set_state ↦ gensem set_state0_spec
          ⊕ tdqueue_init ↦ gensem tdqueue_init0_spec
          ⊕ enqueue ↦ gensem enqueue0_spec
          ⊕ dequeue ↦ gensem dequeue0_spec
          ⊕ queue_rmv ↦ gensem queue_rmv0_spec

          ⊕ pt_in ↦ primcall_general_compatsem' ptin_spec (prim_ident:= pt_in)
          ⊕ pt_out ↦ primcall_general_compatsem' ptout_spec (prim_ident:= pt_out)
          ⊕ clear_cr2 ↦ gensem clearCR2_spec
          ⊕ container_get_nchildren ↦ gensem container_get_nchildren_spec
          ⊕ container_get_quota ↦ gensem container_get_quota_spec
          ⊕ container_get_usage ↦ gensem container_get_usage_spec
          ⊕ container_can_consume ↦ gensem container_can_consume_spec
          ⊕ container_alloc ↦ gensem alloc_spec
          ⊕ trap_in ↦ primcall_general_compatsem trapin_spec
          ⊕ trap_out ↦ primcall_general_compatsem trapout_spec
          ⊕ host_in ↦ primcall_general_compatsem hostin_spec
          ⊕ host_out ↦ primcall_general_compatsem hostout_spec
          ⊕ trap_get ↦ primcall_trap_info_get_compatsem trap_info_get_spec
          ⊕ trap_set ↦ primcall_trap_info_ret_compatsem trap_info_ret_spec
          ⊕ kctxt_switch ↦ primcall_kctxt_switch_compatsem kctxt_switch_spec
          ⊕ accessors ↦ {| exec_load := @exec_loadex; exec_store := @exec_storeex |}.

  (*Definition semantics := LAsm.Lsemantics pabqueue.*)

End WITHMEM.
