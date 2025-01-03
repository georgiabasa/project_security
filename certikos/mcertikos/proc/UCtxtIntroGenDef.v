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
(*           Layers of PM: Refinement Proof for PUctxtIntro            *)
(*                                                                     *)
(*          Ronghui Gu <ronghui.gu@yale.edu>                           *)
(*                                                                     *)
(*          Yale Flint Group                                           *)
(*                                                                     *)
(* *********************************************************************)

(** This file provide the contextual refinement proof between PIPC layer and PUCtxtIntro layer*)
Require Export Coqlib.
Require Export Errors.
Require Export AST.
Require Export Integers.
Require Export Floats.
Require Export Op.
Require Export Asm.
Require Export Events.
Require Export Globalenvs.
Require Export Smallstep.
Require Export Values.
Require Export Memory.
Require Export Maps.
Require Export CommonTactic.
Require Export AuxLemma.
Require Export FlatMemory.
Require Export AuxStateDataType.
Require Export Constant.
Require Export GlobIdent.
Require Export RealParams.
Require Export LoadStoreSem2.
Require Export AsmImplLemma.
Require Export GenSem.
Require Export RefinementTactic.
Require Export PrimSemantics.
Require Export XOmega.

Require Export liblayers.logic.PTreeModules.
Require Export liblayers.logic.LayerLogicImpl.
Require Export liblayers.compcertx.Stencil.
Require Export liblayers.compcertx.MakeProgram.
Require Export liblayers.compat.CompatLayers.
Require Export liblayers.compat.CompatGenSem.
Require Export compcert.cfrontend.Ctypes.
Require Export LAsmModuleSemAux.
Require Export LayerCalculusLemma.
Require Export AbstractDataType.

Require Export PUCtxtIntro.
Require Export PIPC.

Notation HDATA := RData.
Notation LDATA := RData.

Notation HDATAOps := (cdata (cdata_ops := pipc_data_ops) HDATA).
Notation LDATAOps := (cdata (cdata_ops := pipc_data_ops) LDATA).

Open Scope string_scope.
Open Scope error_monad_scope.
Open Scope Z_scope.

(** * Definition of the refinement relation*)
Section Refinement.

  Context `{real_params: RealParams}.
  
  Section WITHMEM.

    Context `{Hstencil: Stencil}.
    Context `{Hmem: Mem.MemoryModel}.
    Context `{Hmwd: UseMemWithData mem}.

    (** ** Definition the refinement relation: relate_RData + match_RData *)    
    Section REFINEMENT_REL.

      (** Relation between the kernel context pool and the underline memory*)
      Inductive match_UCtxt: stencil -> UContextPool -> mem -> meminj -> Prop :=
      | MATCH_UCTXT:
          forall uctxt m b s f,
            (forall i n,
               0<= i < num_proc
               -> 0<= n < UCTXT_SIZE
               -> (exists v,
                     Mem.load Mint32 m b (i * UCTXT_SIZE * 4 + n * 4) = Some v /\
                     Mem.valid_access m Mint32 b (i * UCTXT_SIZE * 4 + n * 4) Writable /\
                     (*is_valid_context_reg (ZMap.get n (ZMap.get i uctxt)) = true /\*)
                     True /\
                     val_inject f (Val.load_result Mint32 (ZMap.get n (ZMap.get i uctxt))) v))
            -> find_symbol s UCTX_LOC = Some b
            -> match_UCtxt s uctxt m f.

        (** Relation between the new raw data at the higher layer with the mememory at lower layer*)
        Inductive match_RData: stencil -> HDATA -> mem -> meminj -> Prop :=
        | MATCH_RDATA:
            forall hadt m s f,
              match_UCtxt s (uctxt hadt) m f
              -> match_RData s hadt m f.

        (** Relation between raw data at two layers*)
        Record relate_RData (f: meminj) (hadt: HDATA) (ladt: LDATA) :=
          mkrelate_RData {
              flatmem_re: FlatMem.flatmem_inj (HP hadt) (HP ladt);
              vmxinfo_re: vmxinfo hadt = vmxinfo ladt;
              devout_re: devout hadt = devout ladt;
              CR3_re:  CR3 hadt = CR3 ladt;
              ikern_re: ikern hadt = ikern ladt;
              pg_re: pg hadt = pg ladt;
              ihost_re: ihost hadt = ihost ladt;
              AC_re: AC hadt = AC ladt;
              ti_fst_re: (fst (ti hadt)) = (fst (ti ladt));
              ti_snd_re: val_inject f (snd (ti hadt)) (snd (ti ladt));
              LAT_re: LAT hadt = LAT ladt;
              nps_re: nps hadt = nps ladt;
              init_re: init hadt = init ladt;

              pperm_re: pperm hadt = pperm ladt;
              PT_re:  PT hadt = PT ladt;
              ptp_re: ptpool hadt = ptpool ladt;
              idpde_re: idpde hadt = idpde ladt;
              ipt_re: ipt hadt = ipt ladt;
              smspool_re: smspool hadt = smspool ladt;

              kctxt_re: kctxt_inj f num_proc (kctxt hadt) (kctxt ladt);
              abtcb_re:  abtcb hadt = abtcb ladt;
              abq_re:  abq hadt = abq ladt;
              cid_re:  cid hadt = cid ladt;
              chpool_re:  syncchpool hadt = syncchpool ladt
            }.

        Global Instance rel_ops: CompatRelOps HDATAOps LDATAOps :=
          {
            relate_AbData s f d1 d2 := relate_RData f d1 d2;
            match_AbData s d1 m f := match_RData s d1 m f;
            new_glbl := UCTX_LOC :: nil
          }.

    End REFINEMENT_REL.

    (** ** Properties of relations*)
    Section Rel_Property.

      Lemma inject_match_correct:
        forall s d1 m2 f m2' j,
          match_RData s d1 m2 f ->
          Mem.inject j m2 m2' ->
          inject_incr (Mem.flat_inj (genv_next s)) j ->
          match_RData s d1 m2' (compose_meminj f j).
      Proof.
        inversion 1; subst; intros.
        inv H0.
        assert (HFB0: j b = Some (b, 0)).
        {
          eapply stencil_find_symbol_inject'; eauto.
        }
        econstructor; eauto; intros.
        econstructor; eauto; intros.
        specialize (H3 _ _ H0 H5).
        destruct H3 as [v1[HL1[HV1 [_ HM]]]]. 
        specialize (Mem.load_inject _ _  _ _ _ _ _ _ _ H1 HL1 HFB0).
        repeat rewrite Z.add_0_r. 
        intros [v1'[HLD1' HV1']].
        refine_split'; eauto.
        specialize(Mem.valid_access_inject _ _  _ _ _ _ _ _ _ HFB0 H1 HV1).
        rewrite Z.add_0_r; trivial.
        eapply val_inject_compose; eauto.
      Qed.

      Lemma store_match_correct:
        forall s abd m0 m0' f b2 v v' chunk,
          match_RData s abd m0 f ->
          (forall i b,
             In i new_glbl ->
             find_symbol s i = Some b -> b <> b2) ->
          Mem.store chunk m0 b2 v v' = Some m0' ->
          match_RData s abd m0' f.
      Proof.
        intros. inv H. inv H2.
        econstructor; eauto.
        econstructor; eauto.
        intros. specialize (H _ _ H2 H4).
        destruct H as [v1[HL1[HV1[_ HM]]]]. 
        eapply H0 in H3; simpl; eauto.
        repeat rewrite (Mem.load_store_other  _ _ _ _ _ _ H1); auto.
        refine_split'; eauto;
        eapply Mem.store_valid_access_1; eauto.
      Qed.

      Lemma storebytes_match_correct:
        forall s abd m0 m0' f b2 v v',
          match_RData s abd m0 f ->
          (forall i b,
             In i new_glbl ->
             find_symbol s i = Some b -> b <> b2) ->
          Mem.storebytes m0 b2 v v' = Some m0' ->
          match_RData s abd m0' f.
      Proof.
        intros. inv H. inv H2.
        econstructor; eauto.
        econstructor; eauto. 
        intros. specialize (H _ _ H2 H4).
        destruct H as [v1[HL1[HV1[_ HM]]]]. 
        eapply H0 in H3; simpl; eauto.
        repeat rewrite (Mem.load_storebytes_other _ _ _ _ _ H1); eauto.
        refine_split'; eauto;
        eapply Mem.storebytes_valid_access_1; eauto.
      Qed.

      Lemma free_match_correct:
        forall s abd m0 m0' f ofs sz b2,
          match_RData s abd m0 f->
          (forall i b,
             In i new_glbl ->
             find_symbol s i = Some b -> b <> b2) ->
          Mem.free m0 b2 ofs sz = Some m0' ->
          match_RData s abd m0' f.
      Proof.
        intros; inv H; inv H2.
        econstructor; eauto.
        econstructor; eauto. 
        intros. specialize (H _ _ H2 H4).
        destruct H as [v1[HL1[HV1[_ HM]]]]. 
        eapply H0 in H3; simpl; eauto.
        repeat rewrite (Mem.load_free _ _ _ _ _ H1); auto.
        refine_split'; eauto;
        eapply Mem.valid_access_free_1; eauto.
      Qed.
      
      Lemma alloc_match_correct:
        forall s abd m'0  m'1 f f' ofs sz b0 b'1,
          match_RData s abd m'0 f->
          Mem.alloc m'0 ofs sz = (m'1, b'1) ->
          f' b0 = Some (b'1, 0%Z) ->
          (forall b : block, b <> b0 -> f' b = f b) ->
          inject_incr f f' ->
          (forall i b,
             In i new_glbl ->
             find_symbol s i = Some b -> b <> b0) ->
          match_RData s abd m'1 f'.
      Proof.
        intros. rename H1 into HF1, H2 into HB. inv H; inv H1.
        econstructor; eauto.
        econstructor; eauto. 
        intros. specialize (H _ _ H1 H5).
        destruct H as [v1[HL1[HV1[_ HM]]]]. 
        refine_split'; eauto;
        try (apply (Mem.load_alloc_other _ _ _ _ _ H0));          
        try (eapply Mem.valid_access_alloc_other); eauto.
      Qed.

      (** Prove that after taking one step, the refinement relation still holds*)    
      Lemma relate_incr:  
        forall abd abd' f f',
          relate_RData f abd abd'
          -> inject_incr f f'
          -> relate_RData f' abd abd'.
      Proof.
        inversion 1; subst; intros; inv H; constructor; eauto.
        - eapply kctxt_inj_incr; eauto.
      Qed.

      Lemma relate_kernel_mode:
        forall abd abd' f,
          relate_RData f abd abd' 
          -> (kernel_mode abd <-> kernel_mode abd').
      Proof.
        inversion 1; simpl; split; congruence.
      Qed.

      Lemma relate_observe:
        forall p abd abd' f,
          relate_RData f abd abd' ->
          observe p abd = observe p abd'.
      Proof.
        inversion 1; simpl; unfold ObservationImpl.observe; congruence.
      Qed.

      Global Instance rel_prf: CompatRel HDATAOps LDATAOps.
      Proof.
        constructor.
        - apply inject_match_correct.
        - apply store_match_correct.
        - apply alloc_match_correct.
        - apply free_match_correct.
        - apply storebytes_match_correct.
        - intros. eapply relate_incr; eauto.
        - intros; eapply relate_kernel_mode; eauto.
        - intros; eapply relate_observe; eauto.
      Qed.

    End Rel_Property.

  End WITHMEM.

End Refinement.
