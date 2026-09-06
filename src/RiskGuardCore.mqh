//+------------------------------------------------------------------+
//| RiskGuardCore.mqh                                                 |
//| Shared risk-evaluation logic for RiskGuard.mq5 and the test-only  |
//| harness (tests/RiskGuardTestHarness.mq5). Behavior-identical to   |
//| the pre-refactor monolithic RiskGuard.mq5 -- only the entry-point |
//| functions (OnInit/OnDeinit/OnTimer/OnTradeTransaction) live       |
//| outside this header, so both programs run the exact same checks. |
//+------------------------------------------------------------------+
#property copyright "Dev Art Solutions"
#property link      "https://devart.solutions"

#include <Trade/Trade.mqh>

enum ENUM_RISKGUARD_STATE
  {
   RISK_SAFE = 0,
   RISK_RESTRICTED = 1,
   RISK_BLOCKED = 2,
   RISK_EMERGENCY = 3
  };

input group "Daily account limits"
input double MaxDailyLossPercent = 3.0;
input double MaxRiskPerTradePercent = 1.0;
input int    MaxOpenPositions = 3;
input int    MaxTradesPerDay = 5;
input bool   RejectTradesWithoutSL = true;

input group "Broker-time session"
input bool UseTradingHours = true;
input int  TradingStartHour = 8;
input int  TradingStartMinute = 0;
input int  TradingEndHour = 18;
input int  TradingEndMinute = 0;

input group "Execution conditions"
input int MaxSpreadPoints = 30;

input group "Emergency and liquidation (destructive actions default OFF)"
input bool EmergencyStop = false;
input bool ClosePositionsOnEmergencyStop = false;
input bool ClosePositionsOnDailyLossBreach = false;

input group "Scope (0 = all account positions and trades)"
input long MagicNumberFilter = 0;

input group "Notifications"
input bool EnableTerminalAlerts = true;
input bool EnablePushNotifications = false;

CTrade trade;

const int LIQUIDATION_MAX_BATCHES = 3;
const int LIQUIDATION_RETRY_DELAY_SECONDS = 5;

ENUM_RISKGUARD_STATE current_state = RISK_SAFE;
string current_reason = "NONE";
string active_violations = "";
double day_start_equity = 0.0;
double daily_loss_percent = 0.0;
int trades_today = 0;
int open_positions = 0;
int current_spread_points = 0;
int current_day_id = 0;
datetime current_day_start = 0;
bool daily_loss_locked = false;
bool update_in_progress = false;
bool baseline_persistence_failed = false;
bool daily_lock_persistence_failed = false;
bool emergency_retry_persistence_failed = false;
bool daily_retry_persistence_failed = false;
string global_prefix = "";
string panel_name = "RiskGuard.StatusPanel";

string StateName(const ENUM_RISKGUARD_STATE state)
  {
   switch(state)
     {
      case RISK_EMERGENCY:  return "EMERGENCY";
      case RISK_BLOCKED:    return "BLOCKED";
      case RISK_RESTRICTED: return "RESTRICTED";
      default:              return "SAFE";
     }
  }

void Audit(const string event_name,const string details="")
  {
   if(details == "")
      PrintFormat("[RiskGuard] %s",event_name);
   else
      PrintFormat("[RiskGuard] %s | %s",event_name,details);
  }

void AddViolation(const string reason)
  {
   if(active_violations == "")
      active_violations = reason;
   else
      active_violations += "\n- " + reason;
  }

bool SafeGlobalSet(const string key,const double value,const string context)
  {
   ResetLastError();
   datetime modified=GlobalVariableSet(key,value);
   if(modified==0)
     {
      Audit("GLOBAL_VARIABLE_SET_FAILED",StringFormat("context=%s key=%s error=%d",context,key,GetLastError()));
      return false;
     }
   GlobalVariablesFlush();
   return true;
  }

bool SafeGlobalGet(const string key,double &value,const string context)
  {
   ResetLastError();
   if(!GlobalVariableGet(key,value))
     {
      Audit("GLOBAL_VARIABLE_GET_FAILED",StringFormat("context=%s key=%s error=%d",context,key,GetLastError()));
      return false;
     }
   return true;
  }

uint ServerIdentityHash(const string server)
  {
   // FNV-1a is compact and deterministic; this is namespace separation,
   // not a cryptographic identity or security boundary.
   uint hash=2166136261;
   for(int index=0; index<StringLen(server); ++index)
     {
      hash^=(uint)StringGetCharacter(server,index);
      hash*=16777619;
     }
   return hash;
  }

int BrokerDayId(const datetime value)
  {
   MqlDateTime parts={};
   TimeToStruct(value,parts);
   return parts.year*10000 + parts.mon*100 + parts.day;
  }

datetime BrokerDayStart(const datetime value)
  {
   MqlDateTime parts={};
   TimeToStruct(value,parts);
   parts.hour=0;
   parts.min=0;
   parts.sec=0;
   return StructToTime(parts);
  }

string DayKey(const string suffix)
  {
   return global_prefix + "." + IntegerToString(current_day_id) + "." + suffix;
  }

bool IsPositionInScope()
  {
   if(MagicNumberFilter == 0)
      return true;
   return PositionGetInteger(POSITION_MAGIC) == MagicNumberFilter;
  }

bool IsDealInScope(const ulong deal_ticket)
  {
   if(MagicNumberFilter == 0)
      return true;
   return HistoryDealGetInteger(deal_ticket,DEAL_MAGIC) == MagicNumberFilter;
  }

int CountScopedPositions()
  {
   int count=0;
   for(int index=PositionsTotal()-1; index>=0; --index)
     {
      if(PositionGetTicket(index) == 0)
         continue;
      if(IsPositionInScope())
         ++count;
     }
   return count;
  }

bool ArrayContainsUlong(const ulong &values[],const ulong value)
  {
   for(int index=0; index<ArraySize(values); ++index)
      if(values[index] == value)
         return true;
   return false;
  }

int CountEntryOrdersToday(bool &known)
  {
   known=false;
   datetime now=TimeTradeServer();
   if(!HistorySelect(current_day_start,now))
     {
      Audit("HISTORY_SELECT_FAILED",IntegerToString(GetLastError()));
      return 0;
     }

   ulong counted_orders[];
   int count=0;
   for(int index=0; index<HistoryDealsTotal(); ++index)
     {
      ulong deal_ticket=HistoryDealGetTicket(index);
      if(deal_ticket == 0 || !IsDealInScope(deal_ticket))
         continue;

      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket,DEAL_ENTRY);
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket,DEAL_TYPE);
      if((entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) ||
         (type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL))
         continue;

      // One submitted entry order counts as one trade; partial fills of that
      // same order are intentionally de-duplicated. Exit-only deals never count.
      ulong order_ticket=(ulong)HistoryDealGetInteger(deal_ticket,DEAL_ORDER);
      if(order_ticket == 0)
         order_ticket=deal_ticket;
      if(ArrayContainsUlong(counted_orders,order_ticket))
         continue;

      int size=ArraySize(counted_orders);
      ArrayResize(counted_orders,size+1);
      counted_orders[size]=order_ticket;
      ++count;
     }
   known=true;
   return count;
  }

void LoadTradingDay(const bool force=false)
  {
   datetime now=TimeTradeServer();
   int day_id=BrokerDayId(now);
   if(!force && day_id == current_day_id)
      return;

   current_day_id=day_id;
   current_day_start=BrokerDayStart(now);
   baseline_persistence_failed=false;
   daily_lock_persistence_failed=false;
   daily_retry_persistence_failed=false;
   string baseline_key=DayKey("BE");
   string loss_lock_key=DayKey("DL");

   if(GlobalVariableCheck(baseline_key))
     {
      double stored_baseline=0.0;
      if(SafeGlobalGet(baseline_key,stored_baseline,"daily baseline read") && stored_baseline>0.0)
         day_start_equity=stored_baseline;
      else
        {
         day_start_equity=0.0;
         baseline_persistence_failed=true;
        }
     }
   else
     {
      day_start_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(day_start_equity<=0.0 || !SafeGlobalSet(baseline_key,day_start_equity,"daily baseline create"))
         baseline_persistence_failed=true;
     }

   daily_loss_locked=false;
   if(GlobalVariableCheck(loss_lock_key))
     {
      double stored_lock=0.0;
      if(SafeGlobalGet(loss_lock_key,stored_lock,"daily loss lock read"))
         daily_loss_locked=stored_lock>0.5;
      else
         daily_lock_persistence_failed=true;
     }
   Audit("NEW_TRADING_DAY",StringFormat("day=%d baseline_equity=%.2f restored_lock=%s",
                                      current_day_id,day_start_equity,daily_loss_locked?"true":"false"));
  }

bool IsWithinTradingHours()
  {
   if(!UseTradingHours)
      return true;

   MqlDateTime now={};
   TimeToStruct(TimeTradeServer(),now);
   int minute_of_day=now.hour*60+now.min;
   int start=TradingStartHour*60+TradingStartMinute;
   int finish=TradingEndHour*60+TradingEndMinute;

   if(start == finish)
      return true; // Explicitly interpreted as a 24-hour session.
   if(start < finish)
      return minute_of_day>=start && minute_of_day<finish;
   return minute_of_day>=start || minute_of_day<finish; // Spans midnight.
  }

bool EstimateSelectedPositionRisk(double &risk_money,string &reason)
  {
   string symbol=PositionGetString(POSITION_SYMBOL);
   double volume=PositionGetDouble(POSITION_VOLUME);
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double stop_loss=PositionGetDouble(POSITION_SL);
   ENUM_POSITION_TYPE position_type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   risk_money=0.0;
   reason="";
   if(stop_loss <= 0.0)
     {
      reason="POSITION_WITHOUT_SL:"+symbol;
      return false;
     }
   if(volume <= 0.0 || entry <= 0.0)
     {
      reason="RISK_INPUT_INVALID:"+symbol;
      return false;
     }

   ENUM_ORDER_TYPE order_type=(position_type==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double profit_at_stop=0.0;
   ResetLastError();
   if(!OrderCalcProfit(order_type,symbol,volume,entry,stop_loss,profit_at_stop))
     {
      reason="RISK_CALCULATION_UNKNOWN:"+symbol+":"+IntegerToString(GetLastError());
      return false;
     }

   risk_money=MathAbs(MathMin(profit_at_stop,0.0));
   return true;
  }

void EvaluatePositionRisk(bool &blocked,bool &restricted)
  {
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   for(int index=PositionsTotal()-1; index>=0; --index)
     {
      ulong ticket=PositionGetTicket(index);
      if(ticket == 0 || !IsPositionInScope())
         continue;

      double risk_money=0.0;
      string reason="";
      if(!EstimateSelectedPositionRisk(risk_money,reason))
        {
         AddViolation(reason);
         // Missing SL can be downgraded to a restriction only when explicitly
         // permitted. Other unknown calculations are never treated as safe.
         if(StringFind(reason,"POSITION_WITHOUT_SL:")==0 && !RejectTradesWithoutSL)
            restricted=true;
         else
            blocked=true;
         continue;
        }

      if(equity <= 0.0)
        {
         AddViolation("ACCOUNT_EQUITY_NOT_POSITIVE");
         blocked=true;
         continue;
        }

      double risk_percent=risk_money/equity*100.0;
      if(risk_percent > MaxRiskPerTradePercent)
        {
         AddViolation("MAX_RISK_PER_TRADE:"+PositionGetString(POSITION_SYMBOL));
         blocked=true;
        }
     }
  }

bool HasScopedPositions()
  {
   return CountScopedPositions()>0;
  }

void CloseScopedPositions(const string trigger)
  {
   for(int index=PositionsTotal()-1; index>=0; --index)
     {
      ulong ticket=PositionGetTicket(index);
      if(ticket == 0 || !IsPositionInScope())
         continue;

      string symbol=PositionGetString(POSITION_SYMBOL);
      Audit("POSITION_CLOSE_ATTEMPT",StringFormat("trigger=%s ticket=%I64u symbol=%s",trigger,ticket,symbol));
      ResetLastError();
      if(!trade.SetTypeFillingBySymbol(symbol))
        {
         Audit("POSITION_CLOSE_FAILED",StringFormat("stage=filling_mode ticket=%I64u symbol=%s error=%d",
                                                    ticket,symbol,GetLastError()));
         continue;
        }
      ResetLastError();
      bool request_sent=trade.PositionClose(ticket);
      uint retcode=trade.ResultRetcode();
      if(request_sent && (retcode==TRADE_RETCODE_DONE || retcode==TRADE_RETCODE_DONE_PARTIAL))
         Audit("POSITION_CLOSE_SUCCESS",StringFormat("ticket=%I64u retcode=%u",ticket,retcode));
      else
         Audit("POSITION_CLOSE_FAILED",StringFormat("ticket=%I64u retcode=%u description=%s error=%d",
                                                    ticket,retcode,trade.ResultRetcodeDescription(),GetLastError()));
     }
  }

bool LoadRetryValue(const string key,double &value,const string context,bool &persistence_failed)
  {
   value=0.0;
   if(!GlobalVariableCheck(key))
      return true;
   if(SafeGlobalGet(key,value,context))
      return true;
   persistence_failed=true;
   return false;
  }

void ProcessLiquidation(const string trigger,const string count_key,const string time_key,bool &persistence_failed)
  {
   if(persistence_failed || !HasScopedPositions())
      return;

   double stored_count=0.0;
   double stored_time=0.0;
   if(!LoadRetryValue(count_key,stored_count,trigger+" retry count read",persistence_failed) ||
      !LoadRetryValue(time_key,stored_time,trigger+" retry time read",persistence_failed))
      return;

   int attempts=(int)stored_count;
   if(attempts>=LIQUIDATION_MAX_BATCHES)
      return;

   datetime now=TimeTradeServer();
   if(stored_time>0.0 && now-(datetime)stored_time<LIQUIDATION_RETRY_DELAY_SECONDS)
      return;

   int next_attempt=attempts+1;
   // Persist the bounded state before submitting close requests. If either
   // write fails, consume no untracked batch and stop retrying this session.
   if(!SafeGlobalSet(count_key,(double)next_attempt,trigger+" retry count write") ||
      !SafeGlobalSet(time_key,(double)now,trigger+" retry time write"))
     {
      persistence_failed=true;
      Audit("LIQUIDATION_RETRY_PERSISTENCE_FAILED",StringFormat("trigger=%s batch=%d",trigger,next_attempt));
      return;
     }

   int positions_before=CountScopedPositions();
   Audit("LIQUIDATION_BATCH_ATTEMPT",StringFormat("trigger=%s batch=%d/%d positions=%d",
                                                 trigger,next_attempt,LIQUIDATION_MAX_BATCHES,positions_before));
   CloseScopedPositions(trigger);

   int remaining=CountScopedPositions();
   if(remaining==0)
      Audit("LIQUIDATION_COMPLETED",StringFormat("trigger=%s batches=%d",trigger,next_attempt));
   else if(next_attempt>=LIQUIDATION_MAX_BATCHES)
      Audit("LIQUIDATION_MAX_ATTEMPTS_REACHED",StringFormat("trigger=%s attempts=%d remaining_positions=%d",
                                                            trigger,next_attempt,remaining));
   else
      Audit("LIQUIDATION_RETRY_SCHEDULED",StringFormat("trigger=%s next_batch=%d delay_seconds=%d remaining_positions=%d",
                                                       trigger,next_attempt+1,LIQUIDATION_RETRY_DELAY_SECONDS,remaining));
  }

bool DeleteRetryKey(const string key,const string context)
  {
   if(!GlobalVariableCheck(key))
      return true;
   ResetLastError();
   if(!GlobalVariableDel(key))
     {
      Audit("GLOBAL_VARIABLE_DELETE_FAILED",StringFormat("context=%s key=%s error=%d",context,key,GetLastError()));
      return false;
     }
   return true;
  }

void ResetEmergencyRetryState()
  {
   if(emergency_retry_persistence_failed)
      return;
   bool count_deleted=DeleteRetryKey(global_prefix+".EC","emergency retry reset count");
   bool time_deleted=DeleteRetryKey(global_prefix+".ET","emergency retry reset time");
   if(!count_deleted || !time_deleted)
      emergency_retry_persistence_failed=true;
  }

void NotifyStateChange(const ENUM_RISKGUARD_STATE old_state,const string old_reason)
  {
   string message=StringFormat("MT5 RiskGuard: %s -> %s (%s)",StateName(old_state),StateName(current_state),current_reason);
   Audit("STATE_CHANGED",message+" | previous_reason="+old_reason);
   if(EnableTerminalAlerts)
      Alert(message);
   if(EnablePushNotifications && !SendNotification(message))
      Audit("PUSH_NOTIFICATION_FAILED",IntegerToString(GetLastError()));
  }

void RenderPanel(const bool session_active)
  {
   string status=StringFormat(
      "MT5 RiskGuard\n"
      "State: %s\n"
      "Reason: %s\n\n"
      "Daily Loss: %.2f%% / %.2f%%\n"
      "Trades Today: %d / %d\n"
      "Open Positions: %d / %d\n"
      "Spread: %d / %d pts\n"
      "Trading Hours: %s\n\n"
      "Active violations:\n- %s\n\n"
      "Last Check: %s (broker time)",
      StateName(current_state),current_reason,daily_loss_percent,MaxDailyLossPercent,
      trades_today,MaxTradesPerDay,open_positions,MaxOpenPositions,
      current_spread_points,MaxSpreadPoints,session_active?"ACTIVE":"RESTRICTED",
      active_violations==""?"NONE":active_violations,
      TimeToString(TimeTradeServer(),TIME_SECONDS));

   if(ObjectFind(0,panel_name)<0)
     {
      ObjectCreate(0,panel_name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,panel_name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,panel_name,OBJPROP_XDISTANCE,16);
      ObjectSetInteger(0,panel_name,OBJPROP_YDISTANCE,20);
      ObjectSetInteger(0,panel_name,OBJPROP_FONTSIZE,10);
      ObjectSetString(0,panel_name,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,panel_name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,panel_name,OBJPROP_HIDDEN,true);
     }
   color panel_color=clrLimeGreen;
   if(current_state==RISK_RESTRICTED) panel_color=clrGold;
   if(current_state==RISK_BLOCKED) panel_color=clrTomato;
   if(current_state==RISK_EMERGENCY) panel_color=clrRed;
   ObjectSetInteger(0,panel_name,OBJPROP_COLOR,panel_color);
   ObjectSetString(0,panel_name,OBJPROP_TEXT,status);
   ChartRedraw(0);
  }

void EvaluateRisk()
  {
   if(update_in_progress)
      return;
   update_in_progress=true;

   LoadTradingDay();
   active_violations="";
   bool blocked=false;
   bool restricted=false;

   if(!EmergencyStop)
      ResetEmergencyRetryState();

   if(baseline_persistence_failed)
     {
      AddViolation("BASELINE_PERSISTENCE_FAILED");
      blocked=true;
     }
   if(daily_lock_persistence_failed)
     {
      AddViolation("DAILY_LOCK_PERSISTENCE_FAILED");
      blocked=true;
     }
   if(emergency_retry_persistence_failed)
     {
      AddViolation("EMERGENCY_RETRY_PERSISTENCE_FAILED");
      blocked=true;
     }
   if(daily_retry_persistence_failed)
     {
      AddViolation("DAILY_RETRY_PERSISTENCE_FAILED");
      blocked=true;
     }

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(day_start_equity>0.0)
      daily_loss_percent=MathMax(0.0,(day_start_equity-equity)/day_start_equity*100.0);
   else
     {
      daily_loss_percent=0.0;
      AddViolation("DAILY_BASELINE_INVALID");
      blocked=true;
     }

   if(!daily_loss_locked && daily_loss_percent>=MaxDailyLossPercent)
     {
      daily_loss_locked=true;
      if(!SafeGlobalSet(DayKey("DL"),1.0,"daily loss lock write"))
         daily_lock_persistence_failed=true;
      Audit("DAILY_LOSS_BREACHED",StringFormat("loss=%.2f%% limit=%.2f%%",daily_loss_percent,MaxDailyLossPercent));
     }
   if(daily_loss_locked)
     {
      AddViolation("MAX_DAILY_LOSS");
      blocked=true;
     }
   if(daily_lock_persistence_failed && StringFind(active_violations,"DAILY_LOCK_PERSISTENCE_FAILED")<0)
     {
      AddViolation("DAILY_LOCK_PERSISTENCE_FAILED");
      blocked=true;
     }

   bool trade_history_known=false;
   trades_today=CountEntryOrdersToday(trade_history_known);
   if(!trade_history_known)
     {
      AddViolation("TRADE_HISTORY_UNKNOWN");
      blocked=true;
     }
   else if(trades_today>=MaxTradesPerDay)
     {
      AddViolation("MAX_TRADES_PER_DAY");
      blocked=true;
     }

   open_positions=CountScopedPositions();
   if(open_positions>=MaxOpenPositions)
     {
      AddViolation("MAX_OPEN_POSITIONS");
      restricted=true;
     }

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   current_spread_points=(point>0.0 ? (int)MathRound((ask-bid)/point) : 0);
   if(point<=0.0 || ask<=0.0 || bid<=0.0 || ask<bid)
     {
      AddViolation("SPREAD_UNKNOWN");
      restricted=true;
     }
   else if(current_spread_points>MaxSpreadPoints)
     {
      AddViolation("SPREAD_LIMIT");
      restricted=true;
     }

   bool session_active=IsWithinTradingHours();
   if(!session_active)
     {
      AddViolation("OUTSIDE_TRADING_HOURS");
      restricted=true;
     }

   EvaluatePositionRisk(blocked,restricted);

   ENUM_RISKGUARD_STATE old_state=current_state;
   string old_reason=current_reason;
   if(EmergencyStop)
     {
      AddViolation("EMERGENCY_STOP");
      current_state=RISK_EMERGENCY;
      current_reason="EMERGENCY_STOP";
     }
   else if(blocked)
     {
      current_state=RISK_BLOCKED;
      int separator=StringFind(active_violations,"\n");
      current_reason=(separator<0 ? active_violations : StringSubstr(active_violations,0,separator));
     }
   else if(restricted)
     {
      current_state=RISK_RESTRICTED;
      int separator=StringFind(active_violations,"\n");
      current_reason=(separator<0 ? active_violations : StringSubstr(active_violations,0,separator));
     }
   else
     {
      current_state=RISK_SAFE;
      current_reason="NONE";
     }

   if(current_state!=old_state || current_reason!=old_reason)
      NotifyStateChange(old_state,old_reason);

   if(EmergencyStop && ClosePositionsOnEmergencyStop)
      ProcessLiquidation("EMERGENCY_STOP",global_prefix+".EC",global_prefix+".ET",emergency_retry_persistence_failed);
   if(daily_loss_locked && ClosePositionsOnDailyLossBreach)
      ProcessLiquidation("MAX_DAILY_LOSS",DayKey("DC"),DayKey("DT"),daily_retry_persistence_failed);

   RenderPanel(session_active);
   update_in_progress=false;
  }

bool ValidateInputs()
  {
   if(MaxDailyLossPercent<=0.0 || MaxDailyLossPercent>100.0)
     { Audit("INVALID_CONFIGURATION","MaxDailyLossPercent must be in (0, 100]"); return false; }
   if(MaxRiskPerTradePercent<=0.0 || MaxRiskPerTradePercent>100.0)
     { Audit("INVALID_CONFIGURATION","MaxRiskPerTradePercent must be in (0, 100]"); return false; }
   if(MaxOpenPositions<1 || MaxTradesPerDay<1)
     { Audit("INVALID_CONFIGURATION","position and trade limits must be at least 1"); return false; }
   if(MaxSpreadPoints<1)
     { Audit("INVALID_CONFIGURATION","MaxSpreadPoints must be at least 1"); return false; }
   if(TradingStartHour<0 || TradingStartHour>23 || TradingEndHour<0 || TradingEndHour>23 ||
      TradingStartMinute<0 || TradingStartMinute>59 || TradingEndMinute<0 || TradingEndMinute>59)
     { Audit("INVALID_CONFIGURATION","trading hours must be valid broker clock values"); return false; }
   if(MagicNumberFilter<0)
     { Audit("INVALID_CONFIGURATION","MagicNumberFilter cannot be negative"); return false; }
   return true;
  }

// Shared entry-point bodies. Kept here (rather than duplicated in both
// RiskGuard.mq5 and the test harness) so the two programs can never drift
// in behavior. RiskGuardInit() stops short of the initial risk evaluation
// so a caller (the test harness) can open synthetic positions first;
// RiskGuardEmitInitialState() runs that first evaluation and logs it.

int RiskGuardInit()
  {
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   string server=AccountInfoString(ACCOUNT_SERVER);
   if(server=="")
     {
      Audit("INVALID_ACCOUNT_CONTEXT","ACCOUNT_SERVER is empty; persistent state cannot be namespaced safely");
      return INIT_FAILED;
     }
   global_prefix=StringFormat("RG.%08X.%I64d.%I64d",ServerIdentityHash(server),
                              AccountInfoInteger(ACCOUNT_LOGIN),MagicNumberFilter);
   trade.SetAsyncMode(false);
   LoadTradingDay(true);
   EventSetTimer(1);
   Audit("RISK_GUARD_STARTED",StringFormat("scope_magic=%I64d destructive_emergency=%s destructive_daily_loss=%s",
                                          MagicNumberFilter,ClosePositionsOnEmergencyStop?"true":"false",
                                          ClosePositionsOnDailyLossBreach?"true":"false"));
   return INIT_SUCCEEDED;
  }

void RiskGuardEmitInitialState()
  {
   EvaluateRisk();
   Audit("INITIAL_STATE",StringFormat("state=%s reason=%s",StateName(current_state),current_reason));
  }

void RiskGuardDeinit(const int reason)
  {
   EventKillTimer();
   ObjectDelete(0,panel_name);
   Audit("RISK_GUARD_STOPPED",IntegerToString(reason));
  }
