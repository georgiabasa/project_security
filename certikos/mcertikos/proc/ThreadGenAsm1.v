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
(*           Layers of PM: Assembly Verification for Thread            *)
(*                                                                     *)
(*          Ronghui Gu <ronghui.gu@yale.edu>                           *)
(*                                                                     *)
(*          Yale Flint Group                                           *)
(*                                                                     *)
(* *********************************************************************)

Require Import Coqlib.
Require Import Errors.
Require Import AST.
Require Import Integers.
Require Import Floats.
Require Import Op.
Require Import Locations.
Require Import AuxStateDataType.
Require Import Events.
Require Import Globalenvs.
Require Import Smallstep.
Require Import Op.
Require Import Values.
Require Import Memory.
Require Import Maps.
Require Import FlatMemory.
Require Import RefinementTactic.
Require Import AuxLemma.
Require Import RealParams.
Require Import Constant.
Require Import AsmImplLemma.
Require Import AsmImplTactic.
Require Import GlobIdent.
Require Import CommonTactic.

Require Import liblayers.compat.CompatLayers.
Require Import liblayers.compcertx.MakeProgram.
Require Import LAsmModuleSem.
Require Import LAsm.
Require Import liblayers.compat.CompatGenSem.
Require Import PrimSemantics.
Require Import Conventions.

Require Import PThreadSched.
Require Import ThreadGenSpec.
Require Import ThreadGenAsmSource.
Require Import ThreadGenAsmData.

Require Import LAsmModuleSemSpec.
Require Import LRegSet.
Require Import AbstractDataType.

Section ASM_VERIFICATION.

  Local Open Scope string_scope.
  Local Open Scope error_monad_scope.
  Local Open Scope Z_scope.

  Context `{real_params: RealParams}.

    (*	
	.globl thread_sleep
thread_sleep:
       
        movl    0(%esp), %eax // get parameter chan_id

        alloc_stack_frame

        movl    %eax, 8(%esp) // save parameter chan_id
       
        call    get_curid   
        movl    %eax, 0(%esp) // save cid

        movr    2, %eax
        movl    %eax, 4(%esp) // arguements for set_state (cid, 2)
        call    set_state

        movl    0(%esp), %eax // get parameter cid
        movl    %eax, 4(%esp)
        movl    8(%esp), %eax // get parameter cid
        movl    %eax, 0(%esp) // arguements for set_state (cid, 2)

        call    enqueue       // arguments for enqueue (chan_id, cid)

        jmp     thread_sched
     *)

  Notation LDATA := RData.
  Notation LDATAOps := (cdata (cdata_ops := pthreadsched_data_ops) LDATA).

  Section WITHMEM.

    Context `{Hstencil: Stencil}.
    Context `{Hmem: Mem.MemoryModel}.
    Context `{Hmwd: UseMemWithData mem}.
    Context `{make_program_ops: !MakeProgramOps function Ctypes.type fundef unit}.
    Context `{make_program_prf: !MakeProgram function Ctypes.type fundef unit}.

    Ltac accessors_simpl:=
      match goal with
        | |- exec_storeex _ _ _ _ _ _ _ = _ =>
          unfold exec_storeex, LoadStoreSem2.exec_storeex2; 
            simpl; Lregset_simpl_tac; 
            match goal with
              | |- context[Asm.exec_store _ _ _ _ _ _ _ ] =>
                unfold Asm.exec_store; simpl; 
                Lregset_simpl_tac; lift_trivial
            end
        | |- exec_loadex _ _ _ _ _ _ = _ =>
          unfold exec_loadex, LoadStoreSem2.exec_loadex2; 
            simpl; Lregset_simpl_tac; 
            match goal with
              | |- context[Asm.exec_load _ _ _ _ _ _ ] =>
                unfold Asm.exec_load; simpl; 
                Lregset_simpl_tac; lift_trivial
            end
      end.

    Lemma alloc_load_other:
      forall m0 m1 i1 i2 i3 v b1 b2 chunk, 
        Mem.alloc m0 i1 i2 = (m1, b1) ->
        Mem.load chunk m0 b2 i3 = Some v ->
        b1 <> b2.
    Proof.
      red; intros; subst.
      exploit Mem.fresh_block_alloc; eauto.
      eapply Mem.load_valid_access in H0.
      eapply Mem.valid_access_valid_block; eauto.
      eapply Mem.valid_access_implies; eauto.
      constructor.
    Qed.

    Lemma threadsleep_spec:
      forall ge (s: stencil) (rs rs0 rs': regset) b m0 labd labd' n sig,
        find_symbol s thread_sleep = Some b ->
        make_globalenv s (thread_sleep ↦ threadsleep_function) pthreadsched = ret ge ->
        rs PC = Vptr b Int.zero ->
        thread_sleep_spec labd ((Pregmap.init Vundef) # ESP <- (rs ESP) # EDI <- (rs EDI)
                                                      # ESI <- (rs ESI) # EBX <- (rs EBX) # EBP <- 
                                                      (rs EBP) # RA <- (rs RA)) 
                          (Int.unsigned n) = Some (labd', rs0) ->
        asm_invariant (mem := mwd LDATAOps) s rs (m0, labd) ->
        low_level_invariant (Mem.nextblock m0) labd ->
        high_level_invariant labd ->
        sig = mksignature (AST.Tint::nil) None cc_default ->
        extcall_arguments rs m0 sig (Vint n ::nil) ->
        let rs' := (undef_regs (CR ZF :: CR CF :: CR PF :: CR SF :: CR OF
                                   :: IR EDX :: IR ECX :: IR EAX :: RA :: nil)
                               (undef_regs (List.map preg_of destroyed_at_call) rs)) in

        exists f' m0' r_, 
          lasm_step (thread_sleep ↦ threadsleep_function) (pthreadsched (Hmwd:= Hmwd) (Hmem:= Hmem)) thread_sleep s rs 
                    (m0, labd) r_ (m0', labd')
          /\ inject_incr (Mem.flat_inj (Mem.nextblock m0)) f' 
          /\ Memtype.Mem.inject f' m0 m0'
          /\ (Mem.nextblock m0 <= Mem.nextblock m0')%positive
          /\ (forall l,
                Val.lessdef (Pregmap.get l (rs'#ESP<- (rs0#ESP)#EDI <- (rs0#EDI)#ESI <- (rs0#ESI)#EBX <- (rs0#EBX)
                                               #EBP <- (rs0#EBP)#PC <- (rs0#RA)))
                            (Pregmap.get l r_)).
    Proof.
      intros. inv H3.
      rename H4 into HLOW, H7 into HAN, H5 into Hhigh.
      assert (HOS': 0 <= 64 <= Int.max_unsigned)
        by (rewrite int_max; omega).
        
      caseEq(Mem.alloc m0 0 20).
      intros m1 b0 HALC.
      exploit (make_globalenv_stencil_matches (D:= LDATAOps)); eauto.
      intros Hstencil_matches.

      assert (Hblock: Ple (Genv.genv_next ge) b0 /\ Plt b0 (Mem.nextblock m1)).
      {
        erewrite Mem.nextblock_alloc; eauto.
        apply Mem.alloc_result in HALC.
        rewrite HALC. 
        inv inv_inject_neutral.
        inv Hstencil_matches.
        rewrite stencil_matches_genv_next.
        lift_unfold.
        split; xomega.
      }

      exploit Hthread_sched; eauto.
      intros [[b_sched [Hsched Hsched_fun]] prim_thread_sched].
      exploit Hget_curid; eauto.
      intros [[b_get_cid [Hcid_symbol Hcid_fun]] prim_get_curid].
      exploit Henqueue; eauto.
      intros [[b_enqueue [Henqueue_symbol Henqueue_fun]] prim_enqueue].
      exploit Hset_state; eauto.
      intros [[b_set_state [Hstate_symbol Hstate_fun]] prim_set_state].

      specialize (Mem.valid_access_alloc_same _ _ _ _ _ HALC). intros.

      assert (HV1: Mem.valid_access m1 Mint32 b0 12 Freeable).
      {
        eapply H3; auto; simpl; try omega.
        unfold Z.divide.
        exists 3; omega.
      }
      eapply Mem.valid_access_implies with (p2:= Writable) in HV1; [|constructor].
      destruct (Mem.valid_access_store _ _ _ _ (rs ESP) HV1) as [m2 HST1].
      assert (HV2: Mem.valid_access m2 Mint32 b0 16 Freeable).
      {
        eapply Mem.store_valid_access_1; eauto.
        eapply H3; auto; simpl; try omega.
        unfold Z.divide.
        exists 4; omega.
      }
      eapply Mem.valid_access_implies with (p2:= Writable) in HV2; [|constructor].
      destruct (Mem.valid_access_store _ _ _ _ (rs RA) HV2) as [m3 HST2].
      destruct (threadsleep_generate _ _ _ _ _ _ H2 HLOW Hhigh) as 
          [labd0[labd1[HEX1[HEX2[HEX3[HP[HM1[HM2[HIK[HIH[HIK0[HIH0[HIK1 [HIH1 HCID_range]]]]]]]]]]]]]].
      clear H2 HLOW.

      replace (cid labd) with
      (Int.unsigned (Int.repr (cid labd))) in HEX1, HEX2, HEX3. 

      assert (HV3: Mem.valid_access m3 Mint32 b0 8 Freeable).
      {
        eapply Mem.store_valid_access_1; eauto.
        eapply Mem.store_valid_access_1; eauto.
        eapply H3; auto; simpl; try omega.
        exists 2; omega.
      }
      eapply Mem.valid_access_implies with (p2:= Writable) in HV3; [|constructor].
      destruct (Mem.valid_access_store _ _ _ _ (Vint n) HV3) as [m4 HST3].

      assert(Hnextblock4: Mem.nextblock m4 = Mem.nextblock m1).
      {
        rewrite (Mem.nextblock_store _  _ _ _ _ _ HST3); trivial.
        rewrite (Mem.nextblock_store _  _ _ _ _ _ HST2); trivial.
        rewrite (Mem.nextblock_store _  _ _ _ _ _ HST1); trivial.
      }

      assert (HV4: Mem.valid_access m4 Mint32 b0 0 Freeable).
      {
        repeat (eapply Mem.store_valid_access_1; [eassumption|]).
        eapply H3; auto; simpl; try omega.
        apply Zdivide_0.
      }
      eapply Mem.valid_access_implies with (p2:= Writable) in HV4; [|constructor].
      destruct (Mem.valid_access_store _ _ _ _ (Vint (Int.repr (cid labd))) HV4) as [m5 HST4].
      assert (HV5: Mem.valid_access m5 Mint32 b0 4 Freeable).
      {
        repeat (eapply Mem.store_valid_access_1; [eassumption|]).
        eapply H3; auto; simpl; try omega.
        apply Zdivide_refl.
      }
      eapply Mem.valid_access_implies with (p2:= Writable) in HV5; [|constructor].
      destruct (Mem.valid_access_store _ _ _ _ (Vint (Int.repr 2)) HV5) as [m6 HST5].

      assert(Hnextblock6: Mem.nextblock m6 = Mem.nextblock m1).
      {
        rewrite (Mem.nextblock_store _  _ _ _ _ _ HST5); trivial.
        rewrite (Mem.nextblock_store _  _ _ _ _ _ HST4); trivial.
      }

      assert (HV6: Mem.valid_access m6 Mint32 b0 4 Writable).
      {
        eapply Mem.store_valid_access_1; eauto.
      }
      destruct (Mem.valid_access_store _ _ _ _ (Vint (Int.repr (cid labd))) HV6) as [m7 HST6].
      assert (HV7: Mem.valid_access m7 Mint32 b0 0 Writable).
      {
        repeat (eapply Mem.store_valid_access_1; try eassumption).
      }
      destruct (Mem.valid_access_store _ _ _ _ (Vint n) HV7) as [m8 HST7].

      assert(Hnextblock8: Mem.nextblock m8 = Mem.nextblock m1).
      {
        rewrite (Mem.nextblock_store _  _ _ _ _ _ HST7); trivial.
        rewrite (Mem.nextblock_store _  _ _ _ _ _ HST6); trivial.
      }

      assert (HV8: Mem.range_perm m8 b0 0 20 Cur Freeable).
      {
        unfold Mem.range_perm. intros.
        repeat (eapply Mem.perm_store_1; [eassumption|]).
        eapply Mem.perm_alloc_2; eauto.
      }
      destruct (Mem.range_perm_free _ _ _ _ HV8) as [m9 HFree].

      exploit Hthread_sleep; eauto 2. intros Hfunct.

      rewrite (Lregset_rewrite rs).
      refine_split'; try eassumption.
      rewrite H1.
      econstructor; eauto.
       
      (* Pallocframe *)
      one_step_forward'.
      Lregset_simpl_tac.
      lift_trivial.
      change (Int.unsigned (Int.add Int.zero (Int.repr 12))) with 12.
      change (Int.unsigned (Int.add Int.zero (Int.repr 16))) with 16.
      unfold set; simpl.
      rewrite HALC. simpl.
      rewrite HST1. simpl.
      rewrite HST2.
      reflexivity. 
      Lregset_simpl_tac.

      (* movl    0(%esp), %eax *)
      one_step_forward'.
      unfold exec_loadex, LoadStoreSem2.exec_loadex2.
      unfold Asm.exec_load; simpl.
      simpl; Lregset_simpl_tac.      
      change (Int.add Int.zero (Int.repr 0)) with (Int.repr 0).
      inv HAN. inv H6. simpl in H9.
      destruct (Val.add (rs ESP) (Vint (Int.repr 0))); try (inv H9; fail).
      change positive with ident in *.
      rewrite HIH, HIK.
      simpl in H9. simpl. lift_trivial. 
      exploit Mem.load_alloc_other; eauto.
      intros HLD.
      pose proof (alloc_load_other _ _ _ _ _ _ _ _ _ HALC H9) as Hneq'.
      erewrite Mem.load_store_other; eauto.
      erewrite Mem.load_store_other; eauto.
      rewrite HLD.
      reflexivity.
      Lregset_simpl_tac.

      (* movl    %eax, 8(%esp) *)
      one_step_forward'.
      accessors_simpl.
      change (Int.unsigned (Int.add Int.zero (Int.add Int.zero (Int.repr 8)))) with 8.
      unfold set; simpl.
      rewrite HIH, HIK, HST3.
      reflexivity.
      change (Int.add (Int.repr 2) Int.one) with (Int.repr 3).

      (* call get_curid3*)
      one_step_forward'.
      unfold symbol_offset. unfold fundef.
      rewrite Hcid_symbol.
      Lregset_simpl_tac.

      (* call get cid body*)
      econstructor; eauto.
      eapply (LAsm.exec_step_external _ b_get_cid); simpl; eauto 2.
      constructor_gen_sem_intro.
      simpl. econstructor; eauto.
      change positive with ident in *.
      red. red. red. red. red. red.
      rewrite prim_get_curid.
      refine_split'; try reflexivity.
      econstructor; eauto.
      refine_split'; try reflexivity; try eassumption.
      simpl. repeat split. 
      rewrite HEX1.
      reflexivity.

      Lregset_simpl_tac.
      lift_trivial.
      intros. inv H2.
      rewrite Hnextblock4; assumption.
      discriminate.
      discriminate.
      Lregset_simpl_tac.

      (* movl    %eax, 4(%esp) *)
      one_step_forward'.
      accessors_simpl.
      change (Int.unsigned (Int.add Int.zero (Int.add Int.zero (Int.repr 0)))) with 0.
      unfold set; simpl.
      rewrite HIH, HIK, HST4. reflexivity.
 
      (* movr    2, %eax *) 
      one_step_forward'.
      Lregset_simpl_tac' 6.

      (* movl    %eax, 4(%esp) *)
      one_step_forward'.
      accessors_simpl.
      unfold set; simpl.
      change (Int.unsigned (Int.add Int.zero (Int.add Int.zero (Int.repr 4)))) with 4. 
      rewrite HIH, HIK, HST5. reflexivity.
      change (Int.add (Int.repr 6) Int.one) with (Int.repr 7).

      (* call set_state*)
      one_step_forward'.
      unfold symbol_offset. unfold fundef.
      rewrite Hstate_symbol.
      Lregset_simpl_tac.

      (* call set state body*)
      econstructor; eauto.
      eapply (LAsm.exec_step_external _ b_set_state); simpl; eauto 2; repeat simpl_Pregmap.
      constructor_gen_sem_intro; simpl.
      lift_trivial.
      change (Int.unsigned (Int.add Int.zero (Int.repr 0))) with 0. 
      erewrite Mem.load_store_other; eauto; simpl.
      erewrite Mem.load_store_same; eauto; simpl.
      right. left. omega.

      lift_trivial.
      change (Int.unsigned (Int.add Int.zero (Int.repr 4))) with 4.
      erewrite Mem.load_store_same; eauto; simpl.

      simpl. econstructor; eauto.
      red. red. red. red. red. red.
      change positive with ident in *.
      rewrite prim_set_state.
      refine_split'; try reflexivity.
      econstructor; eauto.
      refine_split'; try reflexivity; try eassumption.
      simpl. repeat split. eassumption.
      Lregset_simpl_tac.
      lift_trivial.
      intros. inv H2.
      rewrite Hnextblock6; assumption.
      discriminate.
      discriminate.
      Lregset_simpl_tac.

      (* movl    0(%esp), %eax *)
      one_step_forward'.
      accessors_simpl.
      rewrite HIH0, HIK0.
      change (Int.unsigned (Int.add Int.zero (Int.add Int.zero (Int.repr 0)))) with 0.
      erewrite Mem.load_store_other; eauto; simpl.
      erewrite Mem.load_store_same; eauto.
      right; left; omega.
      Lregset_simpl_tac' 9.
 
      (* movl    %eax, 0(%esp) *)
      one_step_forward'.
      accessors_simpl.
      unfold set; simpl.
      change (Int.unsigned (Int.add Int.zero (Int.add Int.zero (Int.repr 4)))) with 4. 
      rewrite HIH0, HIK0, HST6. reflexivity.

      (* movl    0(%esp), %eax *)
      one_step_forward'.
      accessors_simpl.
      rewrite HIH0, HIK0.
      change (Int.unsigned (Int.add Int.zero (Int.add Int.zero (Int.repr 8)))) with 8.
      repeat (erewrite Mem.load_store_other; eauto 1; [|simpl;right; right; omega]).
      erewrite Mem.load_store_same; eauto 1.
      Lregset_simpl_tac' 11.
 
      (* movl    %eax, 0(%esp) *)
      one_step_forward'.
      accessors_simpl.
      change (Int.unsigned (Int.add Int.zero (Int.add Int.zero (Int.repr 0)))) with 0. 
      unfold set; simpl.
      rewrite HIH0, HIK0, HST7. reflexivity.
      change (Int.add (Int.repr 11) Int.one) with (Int.repr 12).
 
      (* call enqueue*)
      one_step_forward'.
      unfold symbol_offset. unfold fundef.
      rewrite Henqueue_symbol.          
      Lregset_simpl_tac.

      (* call enqueue body*) 
      econstructor; eauto.
      eapply (LAsm.exec_step_external _ b_enqueue); simpl; eauto 2; trivial.
      constructor_gen_sem_intro; simpl.
      lift_trivial.
      change (Int.unsigned (Int.add Int.zero (Int.repr 0))) with 0.
      erewrite Mem.load_store_same; eauto.
      lift_trivial.
      change (Int.unsigned (Int.add Int.zero (Int.repr 4))) with 4.
      erewrite Mem.load_store_other; eauto; simpl.
      erewrite Mem.load_store_same; eauto.
      right. right. omega.

      simpl. econstructor; eauto.
      red. red. red. red. red. red.
      change positive with ident in *.
      rewrite prim_enqueue.
      refine_split'; try reflexivity.
      econstructor; eauto.
      refine_split'; try reflexivity; try eassumption.
      simpl. repeat split. eassumption.
      Lregset_simpl_tac.
      lift_trivial.
      intros. inv H2.
      rewrite Hnextblock8; assumption.
      discriminate.
      discriminate.
      Lregset_simpl_tac.
 
      (* freeframe *)
      one_step_forward'.
      lift_trivial.
      change (Int.unsigned (Int.add Int.zero (Int.repr 12))) with 12.
      change (Int.unsigned (Int.add Int.zero (Int.repr 16))) with 16.
      unfold set; simpl.
      repeat(erewrite Mem.load_store_other; [|eassumption| simpl; right; right; omega]).
      erewrite Mem.load_store_same; eauto 1.
      erewrite register_type_load_result.

      repeat(erewrite Mem.load_store_other; [|eassumption | simpl; right; right; omega]).
      erewrite Mem.load_store_other; eauto 1.
      erewrite Mem.load_store_same; eauto 1.
      erewrite register_type_load_result.

      rewrite HFree. reflexivity.
      apply inv_reg_wt.
      right; left. simpl. omega.
      apply inv_reg_wt.
      Lregset_simpl_tac' 14.

      (* jmp thread_sched *) 
      one_step_forward'.
      unfold symbol_offset. unfold fundef.
      rewrite Hsched. 
      Lregset_simpl_tac.

      (* call thread_sched body*)  
      eapply star_one; eauto 1.
      eapply (LAsm.exec_step_prim_call _ b_sched); eauto 1. 
      econstructor.
      refine_split'; eauto 1.
      econstructor; eauto 1. simpl.
      econstructor.
      apply HP.
      eassumption.
      intros.
      rewrite (Mem.nextblock_free _ _ _ _ _ HFree); trivial.
      rewrite Hnextblock8.
      erewrite Mem.nextblock_alloc; eauto.
      specialize (HM2 _ _ H2).
      apply val_inject_incr with (Mem.flat_inj (Mem.nextblock m0)); trivial.
      eapply flat_inj_inject_incr. clear. abstract xomega.

      reflexivity.
      inv Hstencil_matches.
      rewrite <- stencil_matches_symbols.
      eassumption.
      reflexivity.
      reflexivity.
      reflexivity.

      assert (HFB: forall b1 delta, Mem.flat_inj (Mem.nextblock m0) b1 <> Some (b0, delta)).
      {
        intros. unfold Mem.flat_inj.
        red; intros.
        destruct (plt b1 (Mem.nextblock m0)). inv H2.
        rewrite (Mem.alloc_result _ _ _ _ _ HALC) in p.
        xomega. inv H2.
      }
      eapply Mem.free_right_inject; eauto 1; [|intros; specialize (HFB b1 delta); apply HFB; trivial].
      repeat (eapply Mem.store_outside_inject; [ | | eassumption] 
              ; [|intros b1 delta; intros; specialize (HFB b1 delta); apply HFB; trivial]).
      eapply Mem.alloc_right_inject; eauto 1.
      inv inv_inject_neutral.
      apply Mem.neutral_inject; trivial.

      rewrite (Mem.nextblock_free _ _ _ _ _ HFree); trivial.
      rewrite Hnextblock8.
      rewrite (Mem.nextblock_alloc _ _ _ _ _ HALC) ; eauto.
      clear. abstract xomega.

      simpl.
      intros reg.
      repeat (rewrite Pregmap.gsspec).
      simpl_destruct_reg.     
      exploit reg_false; try eassumption.
      intros HF. inv HF.

      rewrite Int.unsigned_repr; trivial. 
      omega.
    Qed.

    Lemma thread_sleep_code_correct:
      asm_spec_le (thread_sleep ↦ thread_sleep_spec_low)
                  (〚 thread_sleep ↦ threadsleep_function 〛 pthreadsched).
    Proof.
      eapply asm_sem_intro; try solve [ reflexivity | eexists; reflexivity ].
      intros. inv H.
      eapply make_program_make_globalenv in H0.
      exploit (make_globalenv_stencil_matches (D:= LDATAOps)); eauto.
      intros Hstencil_matches.
      assert(Hfun: Genv.find_funct_ptr (Genv.globalenv p) b =
                     Some (Internal threadsleep_function)).
      {
        assert (Hmodule:
          get_module_function thread_sleep (thread_sleep ↦ threadsleep_function)
            = OK (Some threadsleep_function)) by reflexivity.
        assert (HInternal:
          make_internal threadsleep_function
            = OK (AST.Internal threadsleep_function)) by reflexivity.
        eapply make_globalenv_get_module_function in H0; eauto.
        destruct H0 as [?[Hsymbol ?]].
        inv Hstencil_matches.
        rewrite stencil_matches_symbols in Hsymbol.
        rewrite H1 in Hsymbol. inv Hsymbol.
        assumption.
      }

      exploit threadsleep_spec; eauto 2.
      intros (f' & m0' & r_ & Hstep & Hincr & Hinject & Hnb & Hlessdef).

      split; [ reflexivity |].
      exists f', (m0', labd'), r_.
      repeat split; try assumption.
      simpl; unfold lift; simpl.
      exact (PowersetMonad.powerset_fmap_intro m0' Hinject).
    Qed.

  End WITHMEM.

End ASM_VERIFICATION.