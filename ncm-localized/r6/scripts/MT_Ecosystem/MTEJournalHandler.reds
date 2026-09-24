// ============================================================
// Night City Motorsports: Journal & SMS Handler
//
// Owns the NCM phone contacts, routing choices, and dynamic
// response messages. Gameplay work stays in CET Lua; this service
// makes the in-game phone behave like another race manager front end.
// ============================================================

public class MTEJournalHandler extends ScriptableService {
  private let m_journalToken: ref<ResourceToken>;
  private let m_loaded: Bool;
  private let m_hasContact: Bool;
  private let m_pendingSMSMessageType: Int32;

  private let m_dexContact: ref<JournalContact>;
  private let m_quickieContact: ref<JournalContact>;
  private let m_setupContact: ref<JournalContact>;
  private let m_controlContact: ref<JournalContact>;
  private let m_ledgerContact: ref<JournalContact>;
  private let m_scoutContact: ref<JournalContact>;
  private let m_bookieContact: ref<JournalContact>;

  private let m_dexMenuConvo: ref<JournalPhoneConversation>;
  private let m_quickieMenuConvo: ref<JournalPhoneConversation>;
  private let m_setupMenuConvo: ref<JournalPhoneConversation>;
  private let m_controlMenuConvo: ref<JournalPhoneConversation>;
  private let m_ledgerMenuConvo: ref<JournalPhoneConversation>;
  private let m_scoutMenuConvo: ref<JournalPhoneConversation>;
  private let m_bookieMenuConvo: ref<JournalPhoneConversation>;

  private let m_dexResponseConvo: ref<JournalPhoneConversation>;
  private let m_quickieResponseConvo: ref<JournalPhoneConversation>;
  private let m_setupResponseConvo: ref<JournalPhoneConversation>;
  private let m_controlResponseConvo: ref<JournalPhoneConversation>;
  private let m_ledgerResponseConvo: ref<JournalPhoneConversation>;
  private let m_scoutResponseConvo: ref<JournalPhoneConversation>;
  private let m_bookieResponseConvo: ref<JournalPhoneConversation>;

  private let m_lastResponseSeq: Int32;
  private let m_lastResponseOk: Bool;
  private let m_lastResponseText: String;
  private let m_lastResponseContactId: String;
  private let m_lastTriggeredChoiceText: String;
  private let m_quickieMessageText: String;
  private let m_setupMessageText: String;
  private let m_controlMessageText: String;
  private let m_ledgerMessageText: String;
  private let m_scoutMessageText: String;
  private let m_bookieMessageText: String;
  private let m_bookieMenuBranch: Int32;
  private let m_lastObservedRaceState: Int32;
  private let m_lastObservedQuickieOfferState: Int32;
  private let m_lastObservedDCESContractState: Int32;
  private let m_lastObservedDCESScoutContractState: Int32;
  private let m_lastProcessedSMSSeq: Int32;

  private final func DefaultQuickieMessageText() -> String {
    return "Got one. You in?";
  }

  private final func DefaultSetupMessageText() -> String {
    let contractActive: Int32 = this.GetPhoneFactValue(n"ncm_phone_dces_contract_active");
    if contractActive == 1 {
      return "Stu here. Live contract on the bench. 'Source me parts' locks the package and pushes it to the garage. 'Tune it' passes and kills the lead.";
    }
    return "Pull it onto the lift. I'll tell you what's bolted on, what's sandbagging the chassis, and what I'd change before the next green. If the line is open, I can hang parts and burn you a shop map.";
  }

  private final func DefaultControlMessageText() -> String {
    let builderStep: Int32 = this.GetPhoneFactValue(n"ncm_foreman_builder_step");
    let raceState: Int32 = this.GetPhoneFactValue(n"ncm_race_state");
    let knockoutState: Int32 = this.GetPhoneFactValue(n"ncm_foreman_knockout_state");
    if builderStep == 1 {
      return "Builder step 1/6. Select event type: sprint, drag, or knockout.";
    }
    if builderStep == 2 {
      return "Builder step 2/6. Select field size: 4, 6, 8, or 10 cars.";
    }
    if builderStep == 3 {
      return "Builder step 3/6. Select launch: grid, rolling, or side-by-side.";
    }
    if builderStep == 4 {
      return "Builder step 4/6. Select field pressure: street, serious, or elite.";
    }
    if builderStep == 5 {
      return "Builder step 5/6. Select district: any, Watson, Westbrook, Heywood, Pacifica, Santo Domingo, City Center, or Badlands.";
    }
    if builderStep == 6 {
      return "Builder step 6/6. Draft complete. Confirm deployment or scrap draft.";
    }
    if raceState == 0 {
      if knockoutState == 1 {
        return "Knockout card drafted. Confirm deployment or scrap draft.";
      }
      if knockoutState == 2 {
        return "Knockout card staged. Start race or cancel from board.";
      }
      if knockoutState == 3 {
        return "Knockout countdown live. Abort if run is dead.";
      }
      if knockoutState == 4 {
        return "Knockout run live. Log forfeit / DNF if run is done.";
      }
      if knockoutState == 5 {
        return "Knockout results posted. Clear board when complete.";
      }
    }
    if raceState == 1 {
      return "Race staged. Review, confirm, or cancel from board.";
    }
    if raceState == 2 {
      return "Grid staged. Route to race, run qualifying, start countdown, resolve the managed sim, or cancel board.";
    }
    if raceState == 3 {
      return "Qualifying live. Route to next target or log forfeit / DNF.";
    }
    if raceState == 4 || raceState == 5 {
      return "Race live. Route to next target or log forfeit / DNF if run is done.";
    }
    if raceState == 6 {
      return "Results posted. Clear board or rerun same grid.";
    }
    return "Board's idle. Review the next heat, check ambient, queue management, or stage a run.";
  }

  private final func DefaultLedgerMessageText() -> String {
    return "I archive every time you make this city scream. Want the numbers, or the part where I tell you why everyone's obsessed?";
  }

  private final func DefaultScoutMessageText() -> String {
    let scoutContractActive: Int32 = this.GetPhoneFactValue(n"ncm_phone_dces_scout_contract_active");
    if scoutContractActive == 1 {
      return "Rico here. Live leak on the line. 'Accept contract' takes the intel and folds it into your scout read. 'Decline contract' burns the lead.";
    }
    return "Ask clean and I'll cut the noise. Current grid, pressure points, watch list, or the wider ladder.";
  }

  private final func DefaultBookieMessageText() -> String {
    let raceState: Int32 = this.GetPhoneFactValue(n"ncm_race_state");
    if raceState == 2 {
      return "Board's warm. Pull the winner sheet, take legacy paper, or keep a long ticket breathing before the lights drop.";
    }
    if raceState == 4 || raceState == 5 {
      return "Window's shut while the grid is moving. Read the sheet if you want to stare at your exposure.";
    }
    return "I sell fronted single-race paper, winner slips, and long streak tickets. Pick your risk and wear it.";
  }

  private final func ResetBridgeFacts() -> Void {
    let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(qs) {
      return;
    }

    qs.SetFact(n"ncm_race_active", 0);
    qs.SetFact(n"ncm_race_state", 0);
    qs.SetFact(n"ncm_sms_send_type", 0);
    qs.SetFact(n"ncm_track_id", 0);
    qs.SetFact(n"ncm_finish_pos", 0);
    qs.SetFact(n"ncm_champ_pos", 0);
    qs.SetFact(n"ncm_total_wins", 0);
    qs.SetFact(n"ncm_total_races", 0);
    qs.SetFact(n"ncm_champ_points", 0);
    qs.SetFact(n"ncm_phone_cmd_seq", 0);
    qs.SetFact(n"ncm_phone_cmd_id", 0);
    qs.SetFact(n"ncm_phone_response_seq", 0);
    qs.SetFact(n"ncm_phone_last_processed_seq", 0);
    qs.SetFact(n"ncm_phone_last_result", 0);
    qs.SetFact(n"ncm_phone_bridge_ready", 0);
    qs.SetFact(n"ncm_phone_contact_loaded", 0);
    qs.SetFact(n"ncm_phone_intro_pinged", 0);
    qs.SetFact(n"ncm_phone_debug_seen_seq", 0);
    qs.SetFact(n"ncm_phone_debug_press_seq", 0);
    qs.SetFact(n"ncm_phone_debug_last_cmd", 0);
    qs.SetFact(n"ncm_phone_debug_last_route", 0);
    qs.SetFact(n"ncm_phone_cmd_route", 0);
    qs.SetFact(n"ncm_phone_quickie_offer_active", 0);
    qs.SetFact(n"ncm_phone_dces_contract_active", 0);
    qs.SetFact(n"ncm_phone_dces_scout_contract_active", 0);
    qs.SetFact(n"ncm_foreman_builder_step", 0);
    qs.SetFact(n"ncm_foreman_builder_type", 0);
    qs.SetFact(n"ncm_foreman_knockout_state", 0);
  }

  private cb func OnLoad() {
    this.m_loaded = false;
    this.m_hasContact = false;
    this.m_pendingSMSMessageType = 0;
    this.m_lastResponseText = "NCM link online.";
    this.m_lastResponseContactId = "ncm_motorsports";
    this.m_lastTriggeredChoiceText = "";
    this.m_quickieMessageText = this.DefaultQuickieMessageText();
    this.m_setupMessageText = this.DefaultSetupMessageText();
    this.m_controlMessageText = this.DefaultControlMessageText();
    this.m_ledgerMessageText = this.DefaultLedgerMessageText();
    this.m_scoutMessageText = this.DefaultScoutMessageText();
    this.m_bookieMessageText = this.DefaultBookieMessageText();
    this.m_bookieMenuBranch = 0;
    this.m_lastObservedRaceState = -1;
    this.m_lastObservedQuickieOfferState = -1;
    this.m_lastObservedDCESContractState = -1;
    this.m_lastObservedDCESScoutContractState = -1;
    this.m_lastProcessedSMSSeq = 0;
    this.ResetBridgeFacts();
    this.LoadJournalResource();
    return;
  }

  private cb func OnSessionReady(event: ref<GameSessionEvent>) {
    this.ResetBridgeFacts();
    this.m_pendingSMSMessageType = 0;
    this.m_lastResponseSeq = 0;
    this.m_lastResponseOk = false;
    this.m_lastResponseText = "NCM link online.";
    this.m_lastResponseContactId = "ncm_motorsports";
    this.m_lastTriggeredChoiceText = "";
    this.m_quickieMessageText = this.DefaultQuickieMessageText();
    this.m_setupMessageText = this.DefaultSetupMessageText();
    this.m_controlMessageText = this.DefaultControlMessageText();
    this.m_ledgerMessageText = this.DefaultLedgerMessageText();
    this.m_scoutMessageText = this.DefaultScoutMessageText();
    this.m_bookieMessageText = this.DefaultBookieMessageText();
    this.m_bookieMenuBranch = 0;
    this.m_lastObservedRaceState = -1;
    this.m_lastObservedQuickieOfferState = -1;
    this.m_lastObservedDCESContractState = -1;
    this.m_lastObservedDCESScoutContractState = -1;
    this.m_lastProcessedSMSSeq = 0;
    if !this.m_loaded {
      this.LoadJournalResource();
    }
    if this.m_hasContact {
      this.ActivateContact(false);
    }
    return;
  }

  public final static func GetInstance() -> ref<MTEJournalHandler> {
    return GameInstance.GetScriptableServiceContainer()
      .GetService(NameOf(MTEJournalHandler)) as MTEJournalHandler;
  }

  public final static func Get() -> ref<MTEJournalHandler> {
    return MTEJournalHandler.GetInstance();
  }

  private final func LoadJournalResource() -> Void {
    let depot: ref<ResourceDepot> = GameInstance.GetResourceDepot();
    if !IsDefined(depot) {
      return;
    }

    let path: ResRef = r"mt_ecosystem\\journal\\mt_ecosystem.journal";
    if !depot.ResourceExists(path) {
      return;
    }

    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Resource/Ready", this, n"OnJournalResourceReady")
      .AddTarget(ResourceTarget.Path(path));

    this.m_journalToken = depot.LoadResource(path);
    if !IsDefined(this.m_journalToken) {
      return;
    }

    let journalResource = this.m_journalToken.GetResource() as gameJournalResource;
    if IsDefined(journalResource) {
      this.OnJournalLoadedResource(journalResource);
    }
  }

  private cb func OnJournalResourceReady(event: ref<ResourceEvent>) -> Void {
    let journalResource = event.GetResource() as gameJournalResource;
    if IsDefined(journalResource) {
      this.OnJournalLoadedResource(journalResource);
    }
  }

  private final func OnJournalLoadedResource(journalResource: ref<gameJournalResource>) -> Void {
    if !IsDefined(journalResource) {
      return;
    }

    let rootFolder = journalResource.entry as gameJournalRootFolderEntry;
    if !IsDefined(rootFolder) {
      return;
    }

    let contacts = this.FindPrimaryFolder(rootFolder, "contacts");
    if !IsDefined(contacts) {
      return;
    }

    this.m_dexContact = this.FindContact(contacts, "ncm_motorsports");
    if !IsDefined(this.m_dexContact) {
      return;
    }

    this.m_quickieContact = this.FindContact(contacts, "ncm_quickie");
    this.m_setupContact = this.FindContact(contacts, "ncm_setup_stu");
    this.m_controlContact = this.FindContact(contacts, "ncm_control");
    this.m_ledgerContact = this.FindContact(contacts, "ncm_ledger");
    this.m_scoutContact = this.FindContact(contacts, "ncm_scout");
    this.m_bookieContact = this.FindContact(contacts, "ncm_bookie");

    this.m_dexMenuConvo = this.FindPhoneConversation(this.m_dexContact, "race_setup");
    this.m_quickieMenuConvo = this.FindPhoneConversation(this.m_quickieContact, "quickie_menu");
    this.m_setupMenuConvo = this.FindPhoneConversation(this.m_setupContact, "setup_menu");
    this.m_controlMenuConvo = this.FindPhoneConversation(this.m_controlContact, "control_menu");
    this.m_ledgerMenuConvo = this.FindPhoneConversation(this.m_ledgerContact, "ledger_menu");
    this.m_scoutMenuConvo = this.FindPhoneConversation(this.m_scoutContact, "scout_menu");
    this.m_bookieMenuConvo = this.FindPhoneConversation(this.m_bookieContact, "bookie_menu");

    this.m_dexResponseConvo = this.FindPhoneConversation(this.m_dexContact, "phone_response");
    this.m_quickieResponseConvo = this.FindPhoneConversation(this.m_quickieContact, "phone_response");
    this.m_setupResponseConvo = this.FindPhoneConversation(this.m_setupContact, "phone_response");
    this.m_controlResponseConvo = this.FindPhoneConversation(this.m_controlContact, "phone_response");
    this.m_ledgerResponseConvo = this.FindPhoneConversation(this.m_ledgerContact, "phone_response");
    this.m_scoutResponseConvo = this.FindPhoneConversation(this.m_scoutContact, "phone_response");
    this.m_bookieResponseConvo = this.FindPhoneConversation(this.m_bookieContact, "phone_response");

    this.m_hasContact = true;
    this.m_loaded = true;
    this.ActivateContact(false);
    this.SetPhoneFact(n"ncm_phone_contact_loaded", 1);
    if this.m_pendingSMSMessageType > 0 {
      let pendingType: Int32 = this.m_pendingSMSMessageType;
      this.m_pendingSMSMessageType = 0;
      this.NotifySMS(pendingType);
    }
  }

  private final func SetPhoneFact(factName: CName, value: Int32) -> Void {
    let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
    if IsDefined(qs) {
      qs.SetFact(factName, value);
    }
  }

  private final func GetPhoneFactValue(factName: CName) -> Int32 {
    let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(qs) {
      return 0;
    }
    return qs.GetFact(factName);
  }

  public final func ResetRenderedChoiceTrigger() -> Void {
    this.m_lastTriggeredChoiceText = "";
  }

  private final func ShouldActivateChoiceEntry(contactId: String, choiceId: String) -> Bool {
    if Equals(contactId, "ncm_quickie") {
      let offerActive: Bool = this.GetPhoneFactValue(n"ncm_phone_quickie_offer_active") == 1;
      if Equals(choiceId, "ncm_route_dex") {
        return false;
      }
      if offerActive {
        return Equals(choiceId, "ncm_quickie_confirm_preview") || Equals(choiceId, "ncm_quickie_refresh_offer");
      }
      return Equals(choiceId, "ncm_quick_race") || Equals(choiceId, "ncm_knockout_setup");
    }
    if Equals(contactId, "ncm_setup_stu") {
      if this.GetPhoneFactValue(n"ncm_phone_dces_contract_active") == 1 {
        return Equals(choiceId, "ncm_setup_accept_contract") || Equals(choiceId, "ncm_setup_decline_contract");
      }
      return Equals(choiceId, "ncm_view_car_status")
        || Equals(choiceId, "ncm_get_setup_suggestion")
        || Equals(choiceId, "ncm_open_parts_source")
        || Equals(choiceId, "ncm_open_tuning");
    }
    if Equals(contactId, "ncm_control") {
      let builderStep: Int32 = this.GetPhoneFactValue(n"ncm_foreman_builder_step");
      if builderStep == 1 {
        return Equals(choiceId, "ncm_custom_type_sprint")
          || Equals(choiceId, "ncm_custom_type_drag")
          || Equals(choiceId, "ncm_custom_type_knockout")
          || Equals(choiceId, "ncm_custom_scrap");
      }
      if builderStep == 2 {
        return Equals(choiceId, "ncm_custom_field_four")
          || Equals(choiceId, "ncm_custom_field_six")
          || Equals(choiceId, "ncm_custom_field_eight")
          || Equals(choiceId, "ncm_custom_field_ten")
          || Equals(choiceId, "ncm_custom_scrap");
      }
      if builderStep == 3 {
        return Equals(choiceId, "ncm_custom_start_grid")
          || Equals(choiceId, "ncm_custom_start_rolling")
          || Equals(choiceId, "ncm_custom_start_sidebyside")
          || Equals(choiceId, "ncm_custom_scrap");
      }
      if builderStep == 4 {
        return Equals(choiceId, "ncm_custom_difficulty_street")
          || Equals(choiceId, "ncm_custom_difficulty_serious")
          || Equals(choiceId, "ncm_custom_difficulty_elite")
          || Equals(choiceId, "ncm_custom_scrap");
      }
      if builderStep == 5 {
        return Equals(choiceId, "ncm_custom_location_any")
          || Equals(choiceId, "ncm_custom_location_watson")
          || Equals(choiceId, "ncm_custom_location_westbrook")
          || Equals(choiceId, "ncm_custom_location_heywood")
          || Equals(choiceId, "ncm_custom_location_pacifica")
          || Equals(choiceId, "ncm_custom_location_santo_domingo")
          || Equals(choiceId, "ncm_custom_location_city_center")
          || Equals(choiceId, "ncm_custom_location_badlands")
          || Equals(choiceId, "ncm_custom_scrap");
      }
      if builderStep == 6 {
        return Equals(choiceId, "ncm_custom_confirm") || Equals(choiceId, "ncm_custom_scrap");
      }

      let knockoutState: Int32 = this.GetPhoneFactValue(n"ncm_foreman_knockout_state");
      if knockoutState == 1 {
        return Equals(choiceId, "ncm_confirm_preview") || Equals(choiceId, "ncm_abort");
      }
      if knockoutState == 2 {
        return Equals(choiceId, "ncm_start_race") || Equals(choiceId, "ncm_abort");
      }
      if knockoutState == 3 || knockoutState == 4 {
        return Equals(choiceId, "ncm_forfeit_dnf");
      }
      if knockoutState == 5 {
        return Equals(choiceId, "ncm_close_results");
      }

      let raceState: Int32 = this.GetPhoneFactValue(n"ncm_race_state");
      if raceState == 1 {
        return Equals(choiceId, "ncm_confirm_preview") || Equals(choiceId, "ncm_abort");
      }
      if raceState == 2 {
        return Equals(choiceId, "ncm_track_start")
          || Equals(choiceId, "ncm_start_quali")
          || Equals(choiceId, "ncm_control_ambient_status")
          || Equals(choiceId, "ncm_control_simulate_managed_run")
          || Equals(choiceId, "ncm_abort");
      }
      if raceState == 3 {
        return Equals(choiceId, "ncm_track_start") || Equals(choiceId, "ncm_forfeit_dnf");
      }
      if raceState == 4 || raceState == 5 {
        return Equals(choiceId, "ncm_track_start") || Equals(choiceId, "ncm_forfeit_dnf");
      }
      if raceState == 6 {
        return Equals(choiceId, "ncm_close_results") || Equals(choiceId, "ncm_restart");
      }
      return Equals(choiceId, "ncm_start_career_race")
        || Equals(choiceId, "ncm_open_custom_race_flow")
        || Equals(choiceId, "ncm_control_ambient_status")
        || Equals(choiceId, "ncm_control_stage_live_ambient")
        || Equals(choiceId, "ncm_control_queue_managed_sim")
        || Equals(choiceId, "ncm_control_queue_managed_spectate")
        || Equals(choiceId, "ncm_control_simulate_managed_run");
    }
    if Equals(contactId, "ncm_ledger") {
      return Equals(choiceId, "ncm_view_player_stats") || Equals(choiceId, "ncm_reroll_fan_message");
    }
    if Equals(contactId, "ncm_scout") {
      if this.GetPhoneFactValue(n"ncm_phone_dces_scout_contract_active") == 1 {
        return Equals(choiceId, "ncm_scout_accept_contract") || Equals(choiceId, "ncm_scout_decline_contract");
      }
      let raceState: Int32 = this.GetPhoneFactValue(n"ncm_race_state");
      let hasActiveRaceBoard: Bool = raceState >= 1 && raceState <= 6;
      let hasRaceDayBoard: Bool = raceState >= 2 && raceState <= 6;
      if Equals(choiceId, "ncm_scout_status") {
        return true;
      }
      if Equals(choiceId, "ncm_scout_ambient_heat")
        || Equals(choiceId, "ncm_scout_management_targets")
        || Equals(choiceId, "ncm_scout_sign_target_one")
        || Equals(choiceId, "ncm_scout_sign_target_two")
        || Equals(choiceId, "ncm_scout_sign_target_three") {
        return !hasActiveRaceBoard;
      }
      if Equals(choiceId, "ncm_scout_current_grid")
        || Equals(choiceId, "ncm_scout_field_read")
        || Equals(choiceId, "ncm_scout_watchlist") {
        return hasRaceDayBoard;
      }
      return false;
    }
    if Equals(contactId, "ncm_bookie") {
      let raceState: Int32 = this.GetPhoneFactValue(n"ncm_race_state");
      if raceState == 2 {
        if this.m_bookieMenuBranch == 1 {
          return Equals(choiceId, "ncm_wager_low")
            || Equals(choiceId, "ncm_wager_medium")
            || Equals(choiceId, "ncm_wager_high")
            || Equals(choiceId, "ncm_wager_clear")
            || Equals(choiceId, "ncm_wager_earnings");
        }
        if this.m_bookieMenuBranch == 2 {
          return Equals(choiceId, "ncm_wager_board")
            || Equals(choiceId, "ncm_wager_favorite")
            || Equals(choiceId, "ncm_wager_value")
            || Equals(choiceId, "ncm_wager_pick_self")
            || Equals(choiceId, "ncm_wager_pick_favorite")
            || Equals(choiceId, "ncm_wager_pick_value")
            || Equals(choiceId, "ncm_wager_clear")
            || Equals(choiceId, "ncm_wager_earnings");
        }
        if this.m_bookieMenuBranch == 3 {
          return Equals(choiceId, "ncm_wager_streak_three")
            || Equals(choiceId, "ncm_wager_streak_five")
            || Equals(choiceId, "ncm_wager_clear")
            || Equals(choiceId, "ncm_wager_earnings");
        }
        return Equals(choiceId, "ncm_wager_low")
          || Equals(choiceId, "ncm_wager_earnings")
          || Equals(choiceId, "ncm_wager_board")
          || Equals(choiceId, "ncm_wager_streak_three");
      }
      return Equals(choiceId, "ncm_wager_earnings")
        || Equals(choiceId, "ncm_wager_streak_three")
        || Equals(choiceId, "ncm_wager_streak_five");
    }
    return true;
  }

  private final func DebugRouteCode(contactId: String) -> Int32 {
    if Equals(contactId, "ncm_motorsports") { return 1; }
    if Equals(contactId, "ncm_quickie") { return 2; }
    if Equals(contactId, "ncm_setup_stu") { return 3; }
    if Equals(contactId, "ncm_control") { return 4; }
    if Equals(contactId, "ncm_ledger") { return 5; }
    if Equals(contactId, "ncm_scout") { return 6; }
    if Equals(contactId, "ncm_bookie") { return 7; }
    return 0;
  }

  private final func StampChoiceDebug(commandId: Int32, routeContactId: String, wasPressed: Bool) -> Void {
    let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(qs) {
      return;
    }

    qs.SetFact(n"ncm_phone_debug_last_cmd", commandId);
    qs.SetFact(n"ncm_phone_debug_last_route", this.DebugRouteCode(routeContactId));

    if wasPressed {
      qs.SetFact(n"ncm_phone_debug_press_seq", qs.GetFact(n"ncm_phone_debug_press_seq") + 1);
    } else {
      qs.SetFact(n"ncm_phone_debug_seen_seq", qs.GetFact(n"ncm_phone_debug_seen_seq") + 1);
    }
  }

  private final func MakeContactPath(contactId: String) -> ref<gameJournalPath> {
    let path: ref<gameJournalPath> = new gameJournalPath();
    path.realPath = "contacts/" + contactId;
    path.className = n"gameJournalContact";
    path.fileEntryIndex = -1;
    return path;
  }

  private final func AddPhoneContact(contactId: String, sendNotification: Bool) -> Void {
    let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(qs) || StrLen(contactId) <= 0 {
      return;
    }

    let node: ref<questPhoneManagerNodeDefinition> = new questPhoneManagerNodeDefinition();
    let addContact: ref<questAddRemoveContact_NodeType> = new questAddRemoveContact_NodeType();
    let param: questChangeContactList_NodeTypeParams;
    param.contact = this.MakeContactPath(contactId);
    param.addContact = true;
    param.sendNotification = sendNotification;
    ArrayPush(addContact.params, param);
    node.type = addContact;
    qs.ExecuteNode(node);
  }

  private final func ActivateContact(firstSessionNotify: Bool) -> Void {
    this.ActivateContactById("ncm_motorsports", firstSessionNotify, false);
  }

  private final func ActivateContactById(contactId: String, notifyMainMessage: Bool, sendContactNotification: Bool) -> Void {
    let contact: ref<JournalContact> = this.GetContact(contactId);
    if !IsDefined(contact) {
      return;
    }

    let journal: ref<JournalManager> = GameInstance.GetJournalManager(GetGameInstance());
    if !IsDefined(journal) {
      return;
    }

    let currentState = journal.GetEntryState(contact);
    let firstTime = NotEquals(currentState, gameJournalEntryState.Active);
    let contactPath = "contacts/" + contactId;
    let shouldNotifyContact: Bool = sendContactNotification && firstTime;
    let notifyOption: JournalNotifyOption = shouldNotifyContact ? JournalNotifyOption.Notify : JournalNotifyOption.DoNotNotify;
    if shouldNotifyContact {
      journal.ChangeEntryState(contactPath, "gameJournalContact", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
    }
    journal.ChangeEntryState(contactPath, "gameJournalContact", gameJournalEntryState.Active, notifyOption);
    if firstTime {
      this.AddPhoneContact(contactId, shouldNotifyContact);
    }
    this.ActivateMainConversation(contactId, notifyMainMessage || firstTime && notifyMainMessage);
  }

  private final func EnsureContactActive(contactId: String, sendContactNotification: Bool) -> Void {
    let contact: ref<JournalContact> = this.GetContact(contactId);
    if !IsDefined(contact) {
      return;
    }

    let journal: ref<JournalManager> = GameInstance.GetJournalManager(GetGameInstance());
    if !IsDefined(journal) {
      return;
    }

    let currentState = journal.GetEntryState(contact);
    let firstTime = NotEquals(currentState, gameJournalEntryState.Active);
    let contactPath = "contacts/" + contactId;
    let shouldNotifyContact: Bool = sendContactNotification && firstTime;
    let notifyOption: JournalNotifyOption = shouldNotifyContact ? JournalNotifyOption.Notify : JournalNotifyOption.DoNotNotify;
    if shouldNotifyContact {
      journal.ChangeEntryState(contactPath, "gameJournalContact", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
    }
    journal.ChangeEntryState(contactPath, "gameJournalContact", gameJournalEntryState.Active, notifyOption);
    if firstTime {
      this.AddPhoneContact(contactId, shouldNotifyContact);
    }
  }

  private final func MainMessageId(contactId: String) -> String {
    if Equals(contactId, "ncm_motorsports") { return "msg_welcome"; }
    if Equals(contactId, "ncm_quickie") { return "msg_quickie_intro"; }
    if Equals(contactId, "ncm_setup_stu") { return "msg_setup_intro"; }
    if Equals(contactId, "ncm_control") { return "msg_control_intro"; }
    if Equals(contactId, "ncm_ledger") { return "msg_ledger_intro"; }
    if Equals(contactId, "ncm_scout") { return "msg_scout_intro"; }
    if Equals(contactId, "ncm_bookie") { return "msg_bookie_intro"; }
    return "";
  }

  private final func NotifyMainMessageForContact(contactId: String) -> Void {
    let convoId: String = this.MainConversationId(contactId);
    let messageId: String = this.MainMessageId(contactId);
    if StrLen(convoId) <= 0 || StrLen(messageId) <= 0 {
      return;
    }

    this.NotifyPath("contacts/" + contactId + "/" + convoId + "/" + messageId, "gameJournalPhoneMessage");
  }

  private final func ActivateMainConversation(contactId: String, notifyMessages: Bool) -> Void {
    this.ActivateConversation(contactId, this.MainConversationId(contactId), notifyMessages);
  }

  private final func ShowMainConversationResponse(contactId: String) -> Void {
    if StrLen(contactId) <= 0 {
      return;
    }

    this.ResetRenderedChoiceTrigger();
    this.ActivateContactById(contactId, false, true);
    this.NotifyMainMessageForContact(contactId);
    if !Equals(contactId, "ncm_motorsports") {
      this.ActivateMainConversation("ncm_motorsports", false);
    }
  }

  private final func SyncPhoneState(forceRefresh: Bool) -> Void {
    let raceState: Int32 = this.GetPhoneFactValue(n"ncm_race_state");
    let quickieOfferState: Int32 = this.GetPhoneFactValue(n"ncm_phone_quickie_offer_active");
    let dcesContractState: Int32 = this.GetPhoneFactValue(n"ncm_phone_dces_contract_active");
    let dcesScoutContractState: Int32 = this.GetPhoneFactValue(n"ncm_phone_dces_scout_contract_active");
    let needsRefresh: Bool = forceRefresh || raceState != this.m_lastObservedRaceState || quickieOfferState != this.m_lastObservedQuickieOfferState || dcesContractState != this.m_lastObservedDCESContractState || dcesScoutContractState != this.m_lastObservedDCESScoutContractState;

    if !needsRefresh {
      return;
    }

    this.m_lastObservedRaceState = raceState;
    this.m_lastObservedQuickieOfferState = quickieOfferState;
    this.m_lastObservedDCESContractState = dcesContractState;
    this.m_lastObservedDCESScoutContractState = dcesScoutContractState;
    if quickieOfferState != 1 {
      this.m_quickieMessageText = this.DefaultQuickieMessageText();
    }
    this.m_setupMessageText = this.DefaultSetupMessageText();
    this.m_controlMessageText = this.DefaultControlMessageText();
    this.m_scoutMessageText = this.DefaultScoutMessageText();
    this.m_bookieMessageText = this.DefaultBookieMessageText();
    if raceState != 2 {
      this.ResetBookieMenuBranch();
    }
    if this.m_hasContact {
      this.RefreshAllMenus();
    }
  }

  private final func ApplyLocalForemanBuilderChoice(choiceId: String) -> Void {
    let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(qs) {
      return;
    }

    let builderType: Int32 = qs.GetFact(n"ncm_foreman_builder_type");
    let nextStep: Int32 = -1;

    if Equals(choiceId, "ncm_custom_type_sprint") {
      qs.SetFact(n"ncm_foreman_builder_type", 1);
      nextStep = 2;
    } else {
      if Equals(choiceId, "ncm_custom_type_drag") {
        qs.SetFact(n"ncm_foreman_builder_type", 2);
        nextStep = 2;
      } else {
        if Equals(choiceId, "ncm_custom_type_knockout") {
          qs.SetFact(n"ncm_foreman_builder_type", 3);
          nextStep = 2;
        } else {
          if Equals(choiceId, "ncm_custom_field_four") || Equals(choiceId, "ncm_custom_field_six") || Equals(choiceId, "ncm_custom_field_eight") || Equals(choiceId, "ncm_custom_field_ten") {
            nextStep = builderType == 3 ? 4 : 3;
          } else {
            if Equals(choiceId, "ncm_custom_start_grid") || Equals(choiceId, "ncm_custom_start_rolling") || Equals(choiceId, "ncm_custom_start_sidebyside") {
              nextStep = 4;
            } else {
              if Equals(choiceId, "ncm_custom_difficulty_street") || Equals(choiceId, "ncm_custom_difficulty_serious") || Equals(choiceId, "ncm_custom_difficulty_elite") {
                nextStep = builderType == 3 ? 6 : 5;
              } else {
                if Equals(choiceId, "ncm_custom_location_any") || Equals(choiceId, "ncm_custom_location_watson") || Equals(choiceId, "ncm_custom_location_westbrook") || Equals(choiceId, "ncm_custom_location_heywood") || Equals(choiceId, "ncm_custom_location_pacifica") || Equals(choiceId, "ncm_custom_location_santo_domingo") || Equals(choiceId, "ncm_custom_location_city_center") || Equals(choiceId, "ncm_custom_location_badlands") {
                  nextStep = 6;
                } else {
                  if Equals(choiceId, "ncm_custom_scrap") {
                    qs.SetFact(n"ncm_foreman_builder_type", 0);
                    nextStep = 0;
                  }
                }
              }
            }
          }
        }
      }
    }

    if nextStep >= 0 {
      qs.SetFact(n"ncm_foreman_builder_step", nextStep);
      this.m_controlMessageText = this.DefaultControlMessageText();
      if nextStep > 0 && nextStep < 7 {
        this.RefreshConversationChoices("ncm_control", this.MainConversationId("ncm_control"));
      }
    }
  }

  private final func IsBookieBranchingActive() -> Bool {
    return this.GetPhoneFactValue(n"ncm_race_state") == 2;
  }

  private final func SetBookieMenuBranch(branch: Int32) -> Void {
    this.m_bookieMenuBranch = branch;
  }

  private final func ResetBookieMenuBranch() -> Void {
    this.m_bookieMenuBranch = 0;
  }

  private final func RefreshBookieMenu() -> Void {
    this.RefreshConversationChoices("ncm_bookie", this.MainConversationId("ncm_bookie"));
  }

  private final func HandleBookieChoiceSelection(choiceId: String) -> Bool {
    if !this.IsBookieBranchingActive() {
      this.ResetBookieMenuBranch();
      return false;
    }
    if this.m_bookieMenuBranch == 0 {
      if Equals(choiceId, "ncm_wager_low") {
        this.SetBookieMenuBranch(1);
        this.RefreshBookieMenu();
        return true;
      }
      if Equals(choiceId, "ncm_wager_board") {
        this.SetBookieMenuBranch(2);
        this.RefreshBookieMenu();
        return true;
      }
      if Equals(choiceId, "ncm_wager_streak_three") {
        this.SetBookieMenuBranch(3);
        this.RefreshBookieMenu();
        return true;
      }
      return false;
    }
    if Equals(choiceId, "ncm_wager_earnings") {
      this.ResetBookieMenuBranch();
      this.RefreshBookieMenu();
      return true;
    }
    return false;
  }

  private final func ResolveBookieChoiceOverride(rawText: String) -> String {
    if !this.IsBookieBranchingActive() {
      return "";
    }
    if this.m_bookieMenuBranch == 0 {
      if Equals(rawText, "LocKey#9000160") { return "Single-race paper"; }
      if Equals(rawText, "LocKey#9000207") { return "Winner sheet"; }
      if Equals(rawText, "LocKey#9000166") { return "Streak tickets"; }
      if Equals(rawText, "LocKey#9000164") { return "Open the books"; }
      return "";
    }
    if Equals(rawText, "LocKey#9000164") {
      return "Back to Billie";
    }
    if this.m_bookieMenuBranch == 2 {
      if Equals(rawText, "LocKey#9000207") { return "Show the current board"; }
    }
    return "";
  }

  private final func RefreshConversationChoices(contactId: String, convoId: String) -> Void {
    let convo: ref<JournalPhoneConversation> = this.GetConversation(contactId, convoId);
    if !IsDefined(convo) || StrLen(contactId) <= 0 || StrLen(convoId) <= 0 {
      return;
    }

    let journal: ref<JournalManager> = GameInstance.GetJournalManager(GetGameInstance());
    if !IsDefined(journal) {
      return;
    }

    let basePath = "contacts/" + contactId + "/" + convoId;
    journal.ChangeEntryState(basePath, "gameJournalPhoneConversation", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
    for entry in convo.entries {
      let choiceGroup = entry as JournalPhoneChoiceGroup;
      if IsDefined(choiceGroup) {
        let groupPath = basePath + "/" + choiceGroup.GetId();
        journal.ChangeEntryState(groupPath, "gameJournalPhoneChoiceGroup", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        journal.ChangeEntryState(groupPath, "gameJournalPhoneChoiceGroup", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        for choiceEntry in choiceGroup.entries {
          let choicePath = groupPath + "/" + choiceEntry.GetId();
          journal.ChangeEntryState(choicePath, "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
          if this.ShouldActivateChoiceEntry(contactId, choiceEntry.GetId()) {
            journal.ChangeEntryState(choicePath, "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
          }
        }
      }
    }
  }

  private final func ActivateConversation(contactId: String, convoId: String, notifyMessages: Bool) -> Void {
    let convo: ref<JournalPhoneConversation> = this.GetConversation(contactId, convoId);
    if !IsDefined(convo) || StrLen(contactId) <= 0 || StrLen(convoId) <= 0 {
      return;
    }

    let journal: ref<JournalManager> = GameInstance.GetJournalManager(GetGameInstance());
    if !IsDefined(journal) {
      return;
    }

    let basePath = "contacts/" + contactId + "/" + convoId;
    journal.ChangeEntryState(basePath, "gameJournalPhoneConversation", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
    for entry in convo.entries {
      let msg = entry as JournalPhoneMessage;
      if IsDefined(msg) {
        let msgPath = basePath + "/" + msg.GetId();
        if notifyMessages {
          journal.ChangeEntryState(msgPath, "gameJournalPhoneMessage", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
          journal.ChangeEntryState(msgPath, "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        } else {
          journal.ChangeEntryState(msgPath, "gameJournalPhoneMessage", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
          journal.ChangeEntryState(msgPath, "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        }
      }

      let choiceGroup = entry as JournalPhoneChoiceGroup;
      if IsDefined(choiceGroup) {
        let groupPath = basePath + "/" + choiceGroup.GetId();
        journal.ChangeEntryState(groupPath, "gameJournalPhoneChoiceGroup", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        journal.ChangeEntryState(groupPath, "gameJournalPhoneChoiceGroup", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        for choiceEntry in choiceGroup.entries {
          let choicePath = groupPath + "/" + choiceEntry.GetId();
          journal.ChangeEntryState(choicePath, "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
          if this.ShouldActivateChoiceEntry(contactId, choiceEntry.GetId()) {
            journal.ChangeEntryState(choicePath, "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
          }
        }
      }
    }
  }

  private final func NotifyPath(path: String, className: String) -> Void {
    let journal: ref<JournalManager> = GameInstance.GetJournalManager(GetGameInstance());
    if !IsDefined(journal) {
      return;
    }
    journal.ChangeEntryState(path, className, gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
    journal.ChangeEntryState(path, className, gameJournalEntryState.Active, JournalNotifyOption.Notify);
  }

  private final func NotifyContact(contactId: String) -> Void {
    if StrLen(contactId) <= 0 {
      return;
    }
    this.NotifyPath("contacts/" + contactId, "gameJournalContact");
  }

  public final func OpenContactRoute(contactId: String) -> Void {
    if StrLen(contactId) <= 0 {
      return;
    }

    this.SyncPhoneState(false);

    if Equals(contactId, "ncm_quickie") && this.GetPhoneFactValue(n"ncm_phone_quickie_offer_active") != 1 {
      this.m_quickieMessageText = this.DefaultQuickieMessageText();
    }
    if Equals(contactId, "ncm_setup_stu") && StrLen(this.m_setupMessageText) <= 0 {
      this.m_setupMessageText = this.DefaultSetupMessageText();
    }
    if Equals(contactId, "ncm_control") && StrLen(this.m_controlMessageText) <= 0 {
      this.m_controlMessageText = this.DefaultControlMessageText();
    }
    if Equals(contactId, "ncm_bookie") && StrLen(this.m_bookieMessageText) <= 0 {
      this.m_bookieMessageText = this.DefaultBookieMessageText();
    }
    if Equals(contactId, "ncm_bookie") {
      this.ResetBookieMenuBranch();
    }

    this.ResetRenderedChoiceTrigger();
    this.ActivateContactById(contactId, false, true);
    this.NotifyMainMessageForContact(contactId);
    if !Equals(contactId, "ncm_motorsports") {
      this.ActivateMainConversation("ncm_motorsports", false);
    }
  }

  public final func RefreshAllMenus() -> Void {
    if !this.m_hasContact {
      return;
    }

    this.ActivateMainConversation("ncm_motorsports", false);
    this.ActivateMainConversation("ncm_quickie", false);
    this.ActivateMainConversation("ncm_setup_stu", false);
    this.ActivateMainConversation("ncm_control", false);
    this.ActivateMainConversation("ncm_ledger", false);
    this.ActivateMainConversation("ncm_scout", false);
    this.ActivateMainConversation("ncm_bookie", false);
  }

  public final func OnRaceStateUpdated() -> Void {
    this.SyncPhoneState(false);
  }

  public final func ShouldProcessSMS(seq: Int32) -> Bool {
    if seq <= 0 {
      return true;
    }
    if seq <= this.m_lastProcessedSMSSeq {
      return false;
    }
    this.m_lastProcessedSMSSeq = seq;
    return true;
  }

  public final func NotifySMS(messageType: Int32) -> Void {
    if !this.m_hasContact {
      this.m_pendingSMSMessageType = messageType;
      if !this.m_loaded {
        this.LoadJournalResource();
      }
      return;
    }

    switch messageType {
      case 1:
        this.ActivateContact(false);
        this.NotifyPath("contacts/ncm_motorsports/race_setup/msg_welcome", "gameJournalPhoneMessage");
        this.SetPhoneFact(n"ncm_phone_intro_pinged", 1);
        break;
      case 2:
        this.OpenContactRoute("ncm_control");
        break;
      case 3:
        this.OpenContactRoute("ncm_ledger");
        break;
      case 4:
        this.OpenContactRoute("ncm_ledger");
        break;
      default:
        break;
    }
  }

  public final func SetLastPhoneResponse(seq: Int32, ok: Bool, message: String, returnToControlBoard: Bool, contactOverrideId: String) -> Void {
    this.SyncPhoneState(false);
    this.m_lastResponseSeq = seq;
    this.m_lastResponseOk = ok;
    this.m_lastResponseText = message;

    let contactId: String = contactOverrideId;
    if StrLen(contactId) <= 0 {
      contactId = this.m_lastResponseContactId;
    }
    if StrLen(contactId) <= 0 {
      contactId = "ncm_motorsports";
    }

    if this.m_hasContact {
      if Equals(contactId, "ncm_quickie") && this.GetPhoneFactValue(n"ncm_phone_quickie_offer_active") == 1 {
        this.m_quickieMessageText = message;
        this.EnsureContactActive(contactId, false);
        this.ActivateMainConversation(contactId, true);
        return;
      }

      if Equals(contactId, "ncm_control") {
        let builderStep: Int32 = this.GetPhoneFactValue(n"ncm_foreman_builder_step");
        if builderStep > 0 && builderStep < 7 {
          this.m_controlMessageText = this.DefaultControlMessageText();
          this.RefreshConversationChoices(contactId, this.MainConversationId(contactId));
          if !Equals(contactId, "ncm_motorsports") {
            this.ActivateMainConversation("ncm_motorsports", false);
          }
          return;
        }

        if returnToControlBoard {
          this.m_controlMessageText = this.DefaultControlMessageText();
          this.RefreshConversationChoices(contactId, this.MainConversationId(contactId));
          if !Equals(contactId, "ncm_motorsports") {
            this.ActivateMainConversation("ncm_motorsports", false);
          }
          return;
        }

        this.m_controlMessageText = message;
        this.EnsureContactActive(contactId, false);
        this.ActivateMainConversation(contactId, false);
        return;
      }
      if Equals(contactId, "ncm_setup_stu") {
        this.m_setupMessageText = message;
        this.ShowMainConversationResponse(contactId);
        return;
      }
      if Equals(contactId, "ncm_bookie") {
        this.m_bookieMessageText = message;
      }

      if Equals(contactId, "ncm_ledger") {
        let shouldNotifyLedger: Bool = NotEquals(this.m_ledgerMessageText, message);
        this.m_ledgerMessageText = message;
        this.EnsureContactActive(contactId, false);
        this.ActivateMainConversation(contactId, false);
        if shouldNotifyLedger {
          this.NotifyMainMessageForContact(contactId);
        }
        if !Equals(contactId, "ncm_motorsports") {
          this.ActivateMainConversation("ncm_motorsports", false);
        }
        return;
      }

      if Equals(contactId, "ncm_scout") {
        let shouldNotifyScout: Bool = NotEquals(this.m_scoutMessageText, message);
        this.m_scoutMessageText = message;
        this.EnsureContactActive(contactId, false);
        this.ActivateMainConversation(contactId, false);
        if shouldNotifyScout {
          this.NotifyMainMessageForContact(contactId);
        }
        if !Equals(contactId, "ncm_motorsports") {
          this.ActivateMainConversation("ncm_motorsports", false);
        }
        return;
      }

      this.EnsureContactActive(contactId, false);
      this.ActivateConversation(contactId, "phone_response", true);
    }
  }

  public final func QueueCommand(commandId: Int32, replyContactId: String) -> Void {
    if commandId <= 0 {
      return;
    }

    let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(qs) {
      return;
    }

    this.m_lastResponseContactId = replyContactId;
    if StrLen(this.m_lastResponseContactId) <= 0 {
      this.m_lastResponseContactId = this.ResponseContactForCommandId(commandId);
    }
    if StrLen(this.m_lastResponseContactId) <= 0 {
      this.m_lastResponseContactId = "ncm_motorsports";
    }

    let seq: Int32 = qs.GetFact(n"ncm_phone_cmd_seq") + 1;
    qs.SetFact(n"ncm_phone_cmd_route", this.DebugRouteCode(this.m_lastResponseContactId));
    qs.SetFact(n"ncm_phone_cmd_id", commandId);
    qs.SetFact(n"ncm_phone_cmd_seq", seq);
  }

  public final func HandleChoiceSelection(choiceId: String) -> Bool {
    this.SyncPhoneState(false);
    let routeContactId: String = this.RouteContactForChoiceId(choiceId);
    let commandId: Int32 = this.CommandIdForChoiceId(choiceId);
    let replyContactId: String = this.ReplyContactForChoiceId(choiceId);

    if commandId <= 0 && StrLen(routeContactId) <= 0 {
      return false;
    }

    this.ResetRenderedChoiceTrigger();
    this.StampChoiceDebug(commandId, routeContactId, true);

    if StrLen(routeContactId) > 0 {
      this.OpenContactRoute(routeContactId);
      return true;
    }

    if Equals(replyContactId, "ncm_bookie") && this.HandleBookieChoiceSelection(choiceId) {
      return true;
    }

    if Equals(replyContactId, "ncm_control") {
      this.ApplyLocalForemanBuilderChoice(choiceId);
    }

    this.QueueCommand(commandId, replyContactId);
    return true;
  }

  private final func TriggerRenderedRoute(contactId: String, triggerText: String) -> Void {
    this.m_lastTriggeredChoiceText = triggerText;
    this.StampChoiceDebug(0, contactId, true);
    this.OpenContactRoute(contactId);
  }

  private final func TriggerRenderedCommand(commandId: Int32, replyContactId: String, triggerText: String) -> Void {
    this.m_lastTriggeredChoiceText = triggerText;
    this.StampChoiceDebug(commandId, replyContactId, true);
    this.QueueCommand(commandId, replyContactId);
  }

  private final func MatchesChoiceText(rawText: String, localizedText: String, locKey: String, displayText: String) -> Bool {
    return Equals(rawText, locKey) || Equals(rawText, displayText) || Equals(localizedText, displayText);
  }

  public final func ProcessRenderedChoiceText(rawText: String, localizedText: String) -> Void {
    let compareText: String = localizedText;
    let fallbackText: String = rawText;

    if (StrLen(compareText) <= 0 && StrLen(fallbackText) <= 0) || Equals(this.m_lastTriggeredChoiceText, fallbackText) || Equals(this.m_lastTriggeredChoiceText, compareText) {
      return;
    }

    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000100", "Quick Race") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000100", "Quickie Quinn") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000100", "Need a quick run") {
      this.TriggerRenderedRoute("ncm_quickie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000101", "Setup Tuning") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000101", "Setup Stu") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000101", "Need a proper setup") {
      this.TriggerRenderedRoute("ncm_setup_stu", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000102", "Grid Control") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000102", "Foreman") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000102", "Get race control") {
      this.TriggerRenderedRoute("ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000103", "Stats/History") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000103", "My #1 Fan") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000103", "Show me the numbers") {
      this.TriggerRenderedRoute("ncm_ledger", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000104", "Scouting and Management") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000104", "Rico") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000104", "Need fresh talent") {
      this.TriggerRenderedRoute("ncm_scout", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000105", "Betting") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000105", "BookQueen Billie") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000105", "Put me through to wagers") {
      this.TriggerRenderedRoute("ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000110", "Line me one up") {
      this.TriggerRenderedCommand(11, "ncm_quickie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000111", "Line up a knockout") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000111", "Set up knockout") {
      this.TriggerRenderedCommand(12, "ncm_quickie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000113", "You're on, choom") {
      this.TriggerRenderedCommand(20, "ncm_quickie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000114", "Got anything else?") {
      this.TriggerRenderedCommand(14, "ncm_quickie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000112", "Back to Dex") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000143", "Back to Dex") {
      this.TriggerRenderedRoute("ncm_motorsports", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000120", "Check my car") {
      this.TriggerRenderedCommand(70, "ncm_setup_stu", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000121", "What would you change?") {
      this.TriggerRenderedCommand(71, "ncm_setup_stu", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000122", "Source me parts") {
      this.TriggerRenderedCommand(72, "ncm_setup_stu", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000123", "Tune it") {
      this.TriggerRenderedCommand(73, "ncm_setup_stu", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000223", "Accept contract") {
      this.TriggerRenderedCommand(74, "ncm_setup_stu", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000224", "Decline contract") {
      this.TriggerRenderedCommand(75, "ncm_setup_stu", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000130", "Stage next career race") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000130", "Review next career race") {
      this.TriggerRenderedCommand(10, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000131", "Create a custom race") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000131", "Stage an exhibition heat") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000131", "Build a custom race") {
      this.TriggerRenderedCommand(13, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000184", "Sprint") {
      this.TriggerRenderedCommand(80, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000185", "Drag") {
      this.TriggerRenderedCommand(81, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000186", "Knockout") {
      this.TriggerRenderedCommand(82, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000187", "4-car field") {
      this.TriggerRenderedCommand(83, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000188", "6-car field") {
      this.TriggerRenderedCommand(84, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000189", "8-car field") {
      this.TriggerRenderedCommand(85, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000190", "10-car field") {
      this.TriggerRenderedCommand(86, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000191", "Grid start") {
      this.TriggerRenderedCommand(87, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000192", "Rolling start") {
      this.TriggerRenderedCommand(88, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000193", "Side-by-side start") {
      this.TriggerRenderedCommand(89, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000194", "Street pace") {
      this.TriggerRenderedCommand(90, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000195", "Serious heat") {
      this.TriggerRenderedCommand(91, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000196", "Elite killers") {
      this.TriggerRenderedCommand(92, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000197", "Anywhere") {
      this.TriggerRenderedCommand(93, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000198", "Watson") {
      this.TriggerRenderedCommand(94, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000199", "Westbrook") {
      this.TriggerRenderedCommand(95, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000200", "Heywood") {
      this.TriggerRenderedCommand(96, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000201", "Pacifica") {
      this.TriggerRenderedCommand(97, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000202", "Santo Domingo") {
      this.TriggerRenderedCommand(98, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000203", "City Center") {
      this.TriggerRenderedCommand(99, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000204", "Badlands") {
      this.TriggerRenderedCommand(100, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000205", "Confirm this race") {
      this.TriggerRenderedCommand(101, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000206", "Scrap this build") {
      this.TriggerRenderedCommand(102, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000132", "Confirm current race") {
      this.TriggerRenderedCommand(20, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000133", "Cancel race") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000133", "Cancel current race") {
      this.TriggerRenderedCommand(33, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000139", "Forfeit / DNF") {
      this.TriggerRenderedCommand(33, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000134", "Route me to the race") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000134", "Mark the start") {
      this.TriggerRenderedCommand(30, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000135", "Run qualifying") {
      this.TriggerRenderedCommand(31, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000136", "Start race") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000136", "Start countdown") {
      this.TriggerRenderedCommand(32, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000137", "Clear results") {
      this.TriggerRenderedCommand(34, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000138", "Run it back") {
      this.TriggerRenderedCommand(35, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000140", "How am I doing?") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000140", "Show me the receipts") {
      this.TriggerRenderedCommand(42, "ncm_ledger", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000141", "Say more") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000141", "Tell me what that meant") {
      this.TriggerRenderedCommand(43, "ncm_ledger", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000150", "Who's on your radar?") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000150", "What's happening out there?") {
      this.TriggerRenderedCommand(60, "ncm_scout", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000152", "Who's in this race?") {
      this.TriggerRenderedCommand(61, "ncm_scout", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000153", "What am I up against?") {
      this.TriggerRenderedCommand(62, "ncm_scout", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000154", "Who should I watch?") {
      this.TriggerRenderedCommand(63, "ncm_scout", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000213", "Where's the heat?") {
      this.TriggerRenderedCommand(103, "ncm_scout", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000214", "Show management targets") {
      this.TriggerRenderedCommand(104, "ncm_scout", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000215", "Sign target one") {
      this.TriggerRenderedCommand(105, "ncm_scout", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000216", "Sign target two") {
      this.TriggerRenderedCommand(106, "ncm_scout", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000217", "Sign target three") {
      this.TriggerRenderedCommand(107, "ncm_scout", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000225", "Accept contract") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000225", "Take the leak") {
      this.TriggerRenderedCommand(113, "ncm_scout", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000226", "Decline contract") || this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000226", "Burn the lead") {
      this.TriggerRenderedCommand(114, "ncm_scout", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000218", "Show ambient board") {
      this.TriggerRenderedCommand(108, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000219", "Stage live ambient heat") {
      this.TriggerRenderedCommand(109, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000220", "Queue managed sim") {
      this.TriggerRenderedCommand(110, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000221", "Queue managed spectate") {
      this.TriggerRenderedCommand(111, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000222", "Simulate managed run") {
      this.TriggerRenderedCommand(112, "ncm_control", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000160", "Light contract") {
      this.TriggerRenderedCommand(53, "ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000161", "Standard contract") {
      this.TriggerRenderedCommand(54, "ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000162", "Heavy contract") {
      this.TriggerRenderedCommand(55, "ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000163", "Void the slip") {
      this.TriggerRenderedCommand(51, "ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000164", "Open the books") {
      this.TriggerRenderedCommand(52, "ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000207", "Line me up for this race") {
      this.TriggerRenderedCommand(59, "ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000208", "Who's the favorite?") {
      this.TriggerRenderedCommand(64, "ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000209", "Where's the value?") {
      this.TriggerRenderedCommand(65, "ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000210", "Back me") {
      this.TriggerRenderedCommand(66, "ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000211", "Back the favorite") {
      this.TriggerRenderedCommand(67, "ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000212", "Back the value") {
      this.TriggerRenderedCommand(68, "ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000166", "3-race streak") {
      this.TriggerRenderedCommand(57, "ncm_bookie", fallbackText);
      return;
    }
    if this.MatchesChoiceText(fallbackText, compareText, "LocKey#9000167", "5-race streak") {
      this.TriggerRenderedCommand(58, "ncm_bookie", fallbackText);
      return;
    }
  }

  public final func CommandIdForChoiceId(choiceId: String) -> Int32 {
    if Equals(choiceId, "ncm_status") { return 1; }
    if Equals(choiceId, "ncm_setup_scheduled") { return 10; }
    if Equals(choiceId, "ncm_start_career_race") { return 10; }
    if Equals(choiceId, "ncm_quick_race") { return 11; }
    if Equals(choiceId, "ncm_knockout_setup") { return 12; }
    if Equals(choiceId, "ncm_open_custom_race_flow") { return 13; }
    if Equals(choiceId, "ncm_quickie_refresh_offer") { return 14; }
    if Equals(choiceId, "ncm_quickie_confirm_preview") { return 20; }
    if Equals(choiceId, "ncm_confirm_preview") { return 20; }
    if Equals(choiceId, "ncm_cancel") { return 21; }
    if Equals(choiceId, "ncm_track_start") { return 30; }
    if Equals(choiceId, "ncm_start_quali") { return 31; }
    if Equals(choiceId, "ncm_start_race") { return 32; }
    if Equals(choiceId, "ncm_abort") { return 33; }
    if Equals(choiceId, "ncm_forfeit_dnf") { return 33; }
    if Equals(choiceId, "ncm_close_results") { return 34; }
    if Equals(choiceId, "ncm_restart") { return 35; }
    if Equals(choiceId, "ncm_standings") { return 40; }
    if Equals(choiceId, "ncm_stats") { return 41; }
    if Equals(choiceId, "ncm_view_player_stats") { return 42; }
    if Equals(choiceId, "ncm_reroll_fan_message") { return 43; }
    if Equals(choiceId, "ncm_wager_max") { return 50; }
    if Equals(choiceId, "ncm_wager_clear") { return 51; }
    if Equals(choiceId, "ncm_wager_earnings") { return 52; }
    if Equals(choiceId, "ncm_wager_low") { return 53; }
    if Equals(choiceId, "ncm_wager_medium") { return 54; }
    if Equals(choiceId, "ncm_wager_high") { return 55; }
    if Equals(choiceId, "ncm_wager_streak") { return 56; }
    if Equals(choiceId, "ncm_wager_streak_three") { return 57; }
    if Equals(choiceId, "ncm_wager_streak_five") { return 58; }
    if Equals(choiceId, "ncm_wager_board") { return 59; }
    if Equals(choiceId, "ncm_scout_status") { return 60; }
    if Equals(choiceId, "ncm_scout_current_grid") { return 61; }
    if Equals(choiceId, "ncm_scout_field_read") { return 62; }
    if Equals(choiceId, "ncm_scout_watchlist") { return 63; }
    if Equals(choiceId, "ncm_wager_favorite") { return 64; }
    if Equals(choiceId, "ncm_wager_value") { return 65; }
    if Equals(choiceId, "ncm_wager_pick_self") { return 66; }
    if Equals(choiceId, "ncm_wager_pick_favorite") { return 67; }
    if Equals(choiceId, "ncm_wager_pick_value") { return 68; }
    if Equals(choiceId, "ncm_view_car_status") { return 70; }
    if Equals(choiceId, "ncm_get_setup_suggestion") { return 71; }
    if Equals(choiceId, "ncm_open_parts_source") { return 72; }
    if Equals(choiceId, "ncm_open_tuning") { return 73; }
    if Equals(choiceId, "ncm_setup_accept_contract") { return 74; }
    if Equals(choiceId, "ncm_setup_decline_contract") { return 75; }
    if Equals(choiceId, "ncm_custom_type_sprint") { return 80; }
    if Equals(choiceId, "ncm_custom_type_drag") { return 81; }
    if Equals(choiceId, "ncm_custom_type_knockout") { return 82; }
    if Equals(choiceId, "ncm_custom_field_four") { return 83; }
    if Equals(choiceId, "ncm_custom_field_six") { return 84; }
    if Equals(choiceId, "ncm_custom_field_eight") { return 85; }
    if Equals(choiceId, "ncm_custom_field_ten") { return 86; }
    if Equals(choiceId, "ncm_custom_start_grid") { return 87; }
    if Equals(choiceId, "ncm_custom_start_rolling") { return 88; }
    if Equals(choiceId, "ncm_custom_start_sidebyside") { return 89; }
    if Equals(choiceId, "ncm_custom_difficulty_street") { return 90; }
    if Equals(choiceId, "ncm_custom_difficulty_serious") { return 91; }
    if Equals(choiceId, "ncm_custom_difficulty_elite") { return 92; }
    if Equals(choiceId, "ncm_custom_location_any") { return 93; }
    if Equals(choiceId, "ncm_custom_location_watson") { return 94; }
    if Equals(choiceId, "ncm_custom_location_westbrook") { return 95; }
    if Equals(choiceId, "ncm_custom_location_heywood") { return 96; }
    if Equals(choiceId, "ncm_custom_location_pacifica") { return 97; }
    if Equals(choiceId, "ncm_custom_location_santo_domingo") { return 98; }
    if Equals(choiceId, "ncm_custom_location_city_center") { return 99; }
    if Equals(choiceId, "ncm_custom_location_badlands") { return 100; }
    if Equals(choiceId, "ncm_custom_confirm") { return 101; }
    if Equals(choiceId, "ncm_custom_scrap") { return 102; }
    if Equals(choiceId, "ncm_scout_ambient_heat") { return 103; }
    if Equals(choiceId, "ncm_scout_management_targets") { return 104; }
    if Equals(choiceId, "ncm_scout_sign_target_one") { return 105; }
    if Equals(choiceId, "ncm_scout_sign_target_two") { return 106; }
    if Equals(choiceId, "ncm_scout_sign_target_three") { return 107; }
    if Equals(choiceId, "ncm_control_ambient_status") { return 108; }
    if Equals(choiceId, "ncm_control_stage_live_ambient") { return 109; }
    if Equals(choiceId, "ncm_control_queue_managed_sim") { return 110; }
    if Equals(choiceId, "ncm_control_queue_managed_spectate") { return 111; }
    if Equals(choiceId, "ncm_control_simulate_managed_run") { return 112; }
    if Equals(choiceId, "ncm_scout_accept_contract") { return 113; }
    if Equals(choiceId, "ncm_scout_decline_contract") { return 114; }
    return 0;
  }

  public final func RouteContactForChoiceId(choiceId: String) -> String {
    if Equals(choiceId, "ncm_route_dex") { return "ncm_motorsports"; }
    if Equals(choiceId, "ncm_route_quickie") { return "ncm_quickie"; }
    if Equals(choiceId, "ncm_route_setup_stu") { return "ncm_setup_stu"; }
    if Equals(choiceId, "ncm_route_control") { return "ncm_control"; }
    if Equals(choiceId, "ncm_route_ledger") { return "ncm_ledger"; }
    if Equals(choiceId, "ncm_route_scout") { return "ncm_scout"; }
    if Equals(choiceId, "ncm_route_bookie") { return "ncm_bookie"; }
    return "";
  }

  public final func ReplyContactForChoiceId(choiceId: String) -> String {
    if Equals(choiceId, "ncm_quick_race") { return "ncm_quickie"; }
    if Equals(choiceId, "ncm_knockout_setup") { return "ncm_quickie"; }
    if Equals(choiceId, "ncm_quickie_confirm_preview") { return "ncm_quickie"; }
    if Equals(choiceId, "ncm_quickie_refresh_offer") { return "ncm_quickie"; }
    if Equals(choiceId, "ncm_setup_scheduled") { return "ncm_setup_stu"; }
    if Equals(choiceId, "ncm_start_career_race") { return "ncm_control"; }
    if Equals(choiceId, "ncm_open_custom_race_flow") { return "ncm_control"; }
    if Equals(choiceId, "ncm_confirm_preview") { return "ncm_control"; }
    if Equals(choiceId, "ncm_cancel") { return "ncm_setup_stu"; }
    if Equals(choiceId, "ncm_track_start") { return "ncm_control"; }
    if Equals(choiceId, "ncm_start_quali") { return "ncm_control"; }
    if Equals(choiceId, "ncm_start_race") { return "ncm_control"; }
    if Equals(choiceId, "ncm_abort") { return "ncm_control"; }
    if Equals(choiceId, "ncm_forfeit_dnf") { return "ncm_control"; }
    if Equals(choiceId, "ncm_close_results") { return "ncm_control"; }
    if Equals(choiceId, "ncm_restart") { return "ncm_control"; }
    if Equals(choiceId, "ncm_status") { return "ncm_ledger"; }
    if Equals(choiceId, "ncm_standings") { return "ncm_ledger"; }
    if Equals(choiceId, "ncm_stats") { return "ncm_ledger"; }
    if Equals(choiceId, "ncm_view_player_stats") { return "ncm_ledger"; }
    if Equals(choiceId, "ncm_reroll_fan_message") { return "ncm_ledger"; }
    if Equals(choiceId, "ncm_wager_max") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_clear") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_earnings") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_low") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_medium") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_high") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_streak") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_streak_three") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_streak_five") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_board") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_favorite") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_value") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_pick_self") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_pick_favorite") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_wager_pick_value") { return "ncm_bookie"; }
    if Equals(choiceId, "ncm_scout_status") { return "ncm_scout"; }
    if Equals(choiceId, "ncm_scout_current_grid") { return "ncm_scout"; }
    if Equals(choiceId, "ncm_scout_field_read") { return "ncm_scout"; }
    if Equals(choiceId, "ncm_scout_watchlist") { return "ncm_scout"; }
    if Equals(choiceId, "ncm_scout_ambient_heat") { return "ncm_scout"; }
    if Equals(choiceId, "ncm_scout_management_targets") { return "ncm_scout"; }
    if Equals(choiceId, "ncm_scout_sign_target_one") { return "ncm_scout"; }
    if Equals(choiceId, "ncm_scout_sign_target_two") { return "ncm_scout"; }
    if Equals(choiceId, "ncm_scout_sign_target_three") { return "ncm_scout"; }
    if Equals(choiceId, "ncm_scout_accept_contract") { return "ncm_scout"; }
    if Equals(choiceId, "ncm_scout_decline_contract") { return "ncm_scout"; }
    if Equals(choiceId, "ncm_view_car_status") { return "ncm_setup_stu"; }
    if Equals(choiceId, "ncm_get_setup_suggestion") { return "ncm_setup_stu"; }
    if Equals(choiceId, "ncm_open_parts_source") { return "ncm_setup_stu"; }
    if Equals(choiceId, "ncm_open_tuning") { return "ncm_setup_stu"; }
    if Equals(choiceId, "ncm_setup_accept_contract") { return "ncm_setup_stu"; }
    if Equals(choiceId, "ncm_setup_decline_contract") { return "ncm_setup_stu"; }
    if Equals(choiceId, "ncm_custom_type_sprint") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_type_drag") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_type_knockout") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_field_four") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_field_six") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_field_eight") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_field_ten") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_start_grid") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_start_rolling") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_start_sidebyside") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_difficulty_street") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_difficulty_serious") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_difficulty_elite") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_location_any") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_location_watson") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_location_westbrook") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_location_heywood") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_location_pacifica") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_location_santo_domingo") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_location_city_center") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_location_badlands") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_confirm") { return "ncm_control"; }
    if Equals(choiceId, "ncm_custom_scrap") { return "ncm_control"; }
    if Equals(choiceId, "ncm_control_ambient_status") { return "ncm_control"; }
    if Equals(choiceId, "ncm_control_stage_live_ambient") { return "ncm_control"; }
    if Equals(choiceId, "ncm_control_queue_managed_sim") { return "ncm_control"; }
    if Equals(choiceId, "ncm_control_queue_managed_spectate") { return "ncm_control"; }
    if Equals(choiceId, "ncm_control_simulate_managed_run") { return "ncm_control"; }
    return "";
  }

  private final func ResponseContactForCommandId(commandId: Int32) -> String {
    if commandId == 11 || commandId == 12 || commandId == 14 { return "ncm_quickie"; }
    if commandId >= 70 && commandId <= 75 { return "ncm_setup_stu"; }
    if commandId == 10 || commandId == 13 || commandId == 20 || commandId == 21 || commandId >= 30 && commandId <= 35 || commandId >= 80 && commandId <= 112 { return "ncm_control"; }
    if commandId == 1 || commandId == 40 || commandId == 41 || commandId == 42 || commandId == 43 { return "ncm_ledger"; }
    if commandId >= 50 && commandId <= 58 { return "ncm_bookie"; }
    if commandId >= 60 && commandId <= 63 || commandId >= 103 && commandId <= 107 || commandId == 113 || commandId == 114 { return "ncm_scout"; }
    return "ncm_motorsports";
  }

  public final func ReplaceNCMTokens(text: String) -> String {
    let result: String = text;
    let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(GetGameInstance());
    let runtime: ref<MTERaceRuntime> = MTERaceRuntime.GetInstance();

    if IsDefined(runtime) {
      result = StrReplaceAll(result, "{NCM_TRACK_NAME}", runtime.GetTrackName());
    }

    if IsDefined(qs) {
      let finishPos = qs.GetFact(n"ncm_finish_pos");
      let champPos = qs.GetFact(n"ncm_champ_pos");
      let totalWins = qs.GetFact(n"ncm_total_wins");
      let totalRaces = qs.GetFact(n"ncm_total_races");
      let champPoints = qs.GetFact(n"ncm_champ_points");

      result = StrReplaceAll(result, "{NCM_FINISH_POS}", IntToString(finishPos));
      result = StrReplaceAll(result, "{NCM_CHAMP_POS}", IntToString(champPos));
      result = StrReplaceAll(result, "{NCM_WINS}", IntToString(totalWins));
      result = StrReplaceAll(result, "{NCM_RACES}", IntToString(totalRaces));
      result = StrReplaceAll(result, "{NCM_CHAMP_POINTS}", IntToString(champPoints));
      if totalRaces > 0 {
        let winRate: Float = Cast<Float>(totalWins * 100) / Cast<Float>(totalRaces);
        result = StrReplaceAll(result, "{NCM_WINRATE}", FloatToStringPrec(winRate, 1) + "%");
      } else {
        result = StrReplaceAll(result, "{NCM_WINRATE}", "0%");
      }
    }

    result = StrReplaceAll(result, "{NCM_QUICKIE_MESSAGE}", this.m_quickieMessageText);
    result = StrReplaceAll(result, "{NCM_SETUP_MESSAGE}", this.m_setupMessageText);
    result = StrReplaceAll(result, "{NCM_CONTROL_MESSAGE}", this.m_controlMessageText);
    result = StrReplaceAll(result, "{NCM_LEDGER_MESSAGE}", this.m_ledgerMessageText);
    result = StrReplaceAll(result, "{NCM_SCOUT_MESSAGE}", this.m_scoutMessageText);
    result = StrReplaceAll(result, "{NCM_BOOKIE_MESSAGE}", this.m_bookieMessageText);
    result = StrReplaceAll(result, "{NCM_PHONE_RESPONSE}", this.m_lastResponseText);
    return result;
  }

  private final func MainConversationId(contactId: String) -> String {
    if Equals(contactId, "ncm_motorsports") { return "race_setup"; }
    if Equals(contactId, "ncm_quickie") { return "quickie_menu"; }
    if Equals(contactId, "ncm_setup_stu") { return "setup_menu"; }
    if Equals(contactId, "ncm_control") { return "control_menu"; }
    if Equals(contactId, "ncm_ledger") { return "ledger_menu"; }
    if Equals(contactId, "ncm_scout") { return "scout_menu"; }
    if Equals(contactId, "ncm_bookie") { return "bookie_menu"; }
    return "";
  }

  private final func GetContact(contactId: String) -> ref<JournalContact> {
    if Equals(contactId, "ncm_motorsports") { return this.m_dexContact; }
    if Equals(contactId, "ncm_quickie") { return this.m_quickieContact; }
    if Equals(contactId, "ncm_setup_stu") { return this.m_setupContact; }
    if Equals(contactId, "ncm_control") { return this.m_controlContact; }
    if Equals(contactId, "ncm_ledger") { return this.m_ledgerContact; }
    if Equals(contactId, "ncm_scout") { return this.m_scoutContact; }
    if Equals(contactId, "ncm_bookie") { return this.m_bookieContact; }
    return null;
  }

  private final func GetConversation(contactId: String, convoId: String) -> ref<JournalPhoneConversation> {
    if Equals(contactId, "ncm_motorsports") {
      if Equals(convoId, "race_setup") { return this.m_dexMenuConvo; }
      if Equals(convoId, "phone_response") { return this.m_dexResponseConvo; }
    }
    if Equals(contactId, "ncm_quickie") {
      if Equals(convoId, "quickie_menu") { return this.m_quickieMenuConvo; }
      if Equals(convoId, "phone_response") { return this.m_quickieResponseConvo; }
    }
    if Equals(contactId, "ncm_setup_stu") {
      if Equals(convoId, "setup_menu") { return this.m_setupMenuConvo; }
      if Equals(convoId, "phone_response") { return this.m_setupResponseConvo; }
    }
    if Equals(contactId, "ncm_control") {
      if Equals(convoId, "control_menu") { return this.m_controlMenuConvo; }
      if Equals(convoId, "phone_response") { return this.m_controlResponseConvo; }
    }
    if Equals(contactId, "ncm_ledger") {
      if Equals(convoId, "ledger_menu") { return this.m_ledgerMenuConvo; }
      if Equals(convoId, "phone_response") { return this.m_ledgerResponseConvo; }
    }
    if Equals(contactId, "ncm_scout") {
      if Equals(convoId, "scout_menu") { return this.m_scoutMenuConvo; }
      if Equals(convoId, "phone_response") { return this.m_scoutResponseConvo; }
    }
    if Equals(contactId, "ncm_bookie") {
      if Equals(convoId, "bookie_menu") { return this.m_bookieMenuConvo; }
      if Equals(convoId, "phone_response") { return this.m_bookieResponseConvo; }
    }
    return null;
  }

  private final func FindPrimaryFolder(rootFolder: ref<gameJournalRootFolderEntry>, id: String) -> ref<gameJournalPrimaryFolderEntry> {
    for entry in rootFolder.entries {
      if Equals(entry.id, id) {
        return entry as gameJournalPrimaryFolderEntry;
      }
    }
    return null;
  }

  private final func FindContact(primaryFolder: ref<gameJournalPrimaryFolderEntry>, id: String) -> ref<JournalContact> {
    for entry in primaryFolder.entries {
      if Equals(entry.id, id) {
        return entry as JournalContact;
      }
    }
    return null;
  }

  private final func FindPhoneConversation(contact: ref<JournalContact>, id: String) -> ref<JournalPhoneConversation> {
    if !IsDefined(contact) {
      return null;
    }
    for entry in contact.entries {
      if Equals(entry.id, id) {
        return entry as JournalPhoneConversation;
      }
    }
    return null;
  }
}

@wrapMethod(MessangerItemRenderer)
private final func SetMessageView(const txt: script_ref<String>, type: MessageViewType, const contactName: script_ref<String>) -> Void {
  let rawTxt: String = Deref(txt);
  let plainTxt: String = rawTxt;
  let localizedTxt: String = GetLocalizedText(plainTxt);
  let resolvedContactName: String = Deref(contactName);
  let localizedContactName: String = GetLocalizedText(resolvedContactName);
  if StrLen(localizedTxt) > 0 {
    plainTxt = localizedTxt;
  }
  if StrLen(localizedContactName) > 0 {
    resolvedContactName = localizedContactName;
  }

  let handler: ref<MTEJournalHandler> = MTEJournalHandler.GetInstance();
  if IsDefined(handler) {
    let overrideTxt: String = handler.ResolveBookieChoiceOverride(rawTxt);
    if StrLen(overrideTxt) > 0 {
      wrappedMethod(overrideTxt, type, resolvedContactName);
      return;
    }
  }
  if StrContains(plainTxt, "{NCM_") {
    if IsDefined(handler) {
      let newText = handler.ReplaceNCMTokens(plainTxt);
      wrappedMethod(newText, type, resolvedContactName);
      return;
    }
  }

  if NotEquals(plainTxt, rawTxt) || NotEquals(resolvedContactName, Deref(contactName)) {
    wrappedMethod(plainTxt, type, resolvedContactName);
    return;
  }

  wrappedMethod(txt, type, contactName);
}

@wrapMethod(MessengerDialogViewController)
private func ActivateReply(target: ref<ListItemController>) -> Void {
  let data: ref<JournalEntryListItemData>;
  let entry: wref<JournalEntry>;
  let choiceEntry: wref<JournalPhoneChoiceEntry>;
  let handler: ref<MTEJournalHandler> = MTEJournalHandler.GetInstance();

  if IsDefined(target) && IsDefined(handler) {
    data = target.GetData() as JournalEntryListItemData;
    if IsDefined(data) {
      entry = data.m_entry;
      choiceEntry = entry as JournalPhoneChoiceEntry;
      if IsDefined(choiceEntry) && handler.HandleChoiceSelection(choiceEntry.GetId()) {
        return;
      }
    }
  }

  wrappedMethod(target);
}
