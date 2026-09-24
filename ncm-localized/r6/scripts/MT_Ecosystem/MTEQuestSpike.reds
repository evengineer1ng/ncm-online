// ============================================================
// Night City Motorsports: isolated native quest proof
//
// Manual and disabled by default. This must not be connected to the
// race state machine or phone bridge until the NCPD regression gate passes.
// Operations: 0 disable, 1 enable, 2 activate, 3 complete, 4 status.
// ============================================================

public class MTEQuestSpikeEvent extends Event {
  public let operation: Int32;
}

@addMethod(inkGameController)
private final func MTEQuestSpikePath(realPath: String, className: CName) -> ref<gameJournalPath> {
  let path: ref<gameJournalPath> = new gameJournalPath();
  path.realPath = realPath;
  path.className = className;
  path.fileEntryIndex = -1;
  return path;
}

@addMethod(inkGameController)
private final func MTEQuestSpikeSetState(path: String, className: String, state: gameJournalEntryState, notify: JournalNotifyOption) -> Bool {
  let journal: ref<JournalManager> = GameInstance.GetJournalManager(GetGameInstance());
  if !IsDefined(journal) {
    return false;
  }

  journal.ChangeEntryState(path, className, state, notify);
  return true;
}

@addMethod(inkGameController)
private final func MTEQuestSpikeTrackQuest() -> Bool {
  let quests: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
  if !IsDefined(quests) {
    return false;
  }

  let node: ref<questJournalNodeDefinition> = new questJournalNodeDefinition();
  let track: ref<questJournalTrackQuest_NodeType> = new questJournalTrackQuest_NodeType();
  track.path = this.MTEQuestSpikePath("quests/ncm/ncm_onboarding", n"gameJournalQuest");
  node.type = track;
  quests.ExecuteNode(node);
  return true;
}

@addMethod(inkGameController)
private final func MTEQuestSpikeWriteStatus(code: Int32) -> Void {
  let quests: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
  if IsDefined(quests) {
    quests.SetFact(n"ncm_quest_spike_status", code);
  }
}

@addMethod(inkGameController)
protected cb func OnMTEQuestSpikeEvent(evt: ref<MTEQuestSpikeEvent>) -> Bool {
  let quests: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
  if !IsDefined(quests) {
    return false;
  }

  if evt.operation == 0 {
    quests.SetFact(n"ncm_quest_spike_enabled", 0);
    this.MTEQuestSpikeWriteStatus(0);
    return true;
  }

  if evt.operation == 1 {
    quests.SetFact(n"ncm_quest_spike_enabled", 1);
    this.MTEQuestSpikeWriteStatus(1);
    return true;
  }

  if evt.operation == 4 {
    return true;
  }

  if quests.GetFact(n"ncm_quest_spike_enabled") != 1 {
    this.MTEQuestSpikeWriteStatus(-1);
    return true;
  }

  if evt.operation == 2 {
    // Parent-to-child, once. No forced Inactive -> Active notification loop.
    this.MTEQuestSpikeSetState("quests/ncm/ncm_onboarding", "gameJournalQuest", gameJournalEntryState.Active, JournalNotifyOption.Notify);
    this.MTEQuestSpikeSetState("quests/ncm/ncm_onboarding/contact_dex", "gameJournalQuestPhase", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
    this.MTEQuestSpikeSetState("quests/ncm/ncm_onboarding/contact_dex/contact_dex", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
    this.MTEQuestSpikeTrackQuest();
    this.MTEQuestSpikeWriteStatus(2);
    return true;
  }

  if evt.operation == 3 {
    // Child-to-parent completion, once.
    this.MTEQuestSpikeSetState("quests/ncm/ncm_onboarding/contact_dex/contact_dex", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
    this.MTEQuestSpikeSetState("quests/ncm/ncm_onboarding/contact_dex", "gameJournalQuestPhase", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
    this.MTEQuestSpikeSetState("quests/ncm/ncm_onboarding", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
    this.MTEQuestSpikeWriteStatus(3);
    return true;
  }

  return false;
}

