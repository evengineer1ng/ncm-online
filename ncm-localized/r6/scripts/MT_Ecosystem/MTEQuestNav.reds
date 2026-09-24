// ============================================================
// Night City Motorsports: Quest / Phone Bridge
//
// The live race flow is owned by CET Lua. Redscript owns the phone
// journal shell and passes explicit command choices to Lua through
// quest facts. Lua answers through MTEPhoneResponseEvent.
// ============================================================

public class MTERaceQuestEvent extends Event {
  public let active: Bool;
  public let trackName: String;
}

public class MTERaceStateSyncEvent extends Event {
  public let raceState: Int32;
  public let trackId: Int32;
  public let finishPos: Int32;
  public let champPos: Int32;
  public let totalWins: Int32;
  public let totalRaces: Int32;
}

public class MTESendSMSEvent extends Event {
  public let messageType: Int32;
  public let seq: Int32;
}

public class MTEPhoneResponseEvent extends Event {
  public let seq: Int32;
  public let ok: Bool;
  public let message: String;
  public let builderStep: Int32;
  public let returnToControlBoard: Bool;
  public let contactId: String;
}

public class MTESetCustomWaypointEvent extends Event {
  public let posX: Float;
  public let posY: Float;
  public let posZ: Float;
  public let label: String;
}

public class MTEClearCustomWaypointEvent extends Event {}

@addMethod(inkGameController)
protected cb func OnMTERaceQuestEvent(evt: ref<MTERaceQuestEvent>) -> Bool {
  let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
  if IsDefined(qs) {
    if evt.active {
      qs.SetFact(n"ncm_race_active", 1);
    } else {
      qs.SetFact(n"ncm_race_active", 0);
    }
  }
  return true;
}

@addMethod(inkGameController)
protected cb func OnMTERaceStateSyncEvent(evt: ref<MTERaceStateSyncEvent>) -> Bool {
  let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
  if !IsDefined(qs) {
    return false;
  }

  let previousRaceState: Int32 = qs.GetFact(n"ncm_race_state");
  qs.SetFact(n"ncm_race_state", evt.raceState);
  if evt.trackId >= 0 { qs.SetFact(n"ncm_track_id", evt.trackId); }
  if evt.finishPos >= 0 { qs.SetFact(n"ncm_finish_pos", evt.finishPos); }
  if evt.champPos >= 0 { qs.SetFact(n"ncm_champ_pos", evt.champPos); }
  if evt.totalWins >= 0 { qs.SetFact(n"ncm_total_wins", evt.totalWins); }
  if evt.totalRaces >= 0 { qs.SetFact(n"ncm_total_races", evt.totalRaces); }

  let handler: ref<MTEJournalHandler> = MTEJournalHandler.GetInstance();
  if IsDefined(handler) && previousRaceState != evt.raceState {
    handler.OnRaceStateUpdated();
  }
  return true;
}

@addMethod(inkGameController)
protected cb func OnMTESendSMSEvent(evt: ref<MTESendSMSEvent>) -> Bool {
  let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
  if IsDefined(qs) {
    qs.SetFact(n"ncm_sms_send_type", evt.messageType);
  }

  let handler: ref<MTEJournalHandler> = MTEJournalHandler.GetInstance();
  if IsDefined(handler) && handler.ShouldProcessSMS(evt.seq) {
    handler.NotifySMS(evt.messageType);
  }
  return true;
}

@addMethod(inkGameController)
protected cb func OnMTEPhoneResponseEvent(evt: ref<MTEPhoneResponseEvent>) -> Bool {
  let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
  if IsDefined(qs) && evt.builderStep >= 0 {
    qs.SetFact(n"ncm_foreman_builder_step", evt.builderStep);
  }

  let handler: ref<MTEJournalHandler> = MTEJournalHandler.GetInstance();
  if IsDefined(handler) {
    handler.SetLastPhoneResponse(evt.seq, evt.ok, evt.message, evt.returnToControlBoard, evt.contactId);
  }
  return true;
}

// Mappin bridge (CET -> Redscript)

public class MTEMappinEvent extends Event {
  public let show: Bool;
  public let startX: Float;
  public let startY: Float;
  public let startZ: Float;
  public let finishX: Float;
  public let finishY: Float;
  public let finishZ: Float;
  public let trackSlot: Int32;
}

public class MTEMappinTrackEvent extends Event {
  public let slot: Int32;
}

@addMethod(inkGameController)
protected cb func OnMTEMappinEvent(evt: ref<MTEMappinEvent>) -> Bool {
  let runtime: ref<MTERaceRuntime> = MTERaceRuntime.GetInstance();
  if !IsDefined(runtime) { return false; }

  if !evt.show {
    runtime.ClearRaceMappins();
    return true;
  }
  runtime.PlaceRaceMappins(
    new Vector4(evt.startX, evt.startY, evt.startZ, 0.0),
    new Vector4(evt.finishX, evt.finishY, evt.finishZ, 0.0)
  );
  return true;
}

@addMethod(inkGameController)
protected cb func OnMTEMappinTrackEvent(evt: ref<MTEMappinTrackEvent>) -> Bool {
  let runtime: ref<MTERaceRuntime> = MTERaceRuntime.GetInstance();
  if !IsDefined(runtime) { return false; }
  runtime.TrackRaceMappin(evt.slot);
  return true;
}
