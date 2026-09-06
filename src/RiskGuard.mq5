#property copyright "Dev Art Solutions"
#property link      "https://devart.solutions"
#property version   "1.00"
#property strict
#property description "Strategy-agnostic account risk monitoring and enforcement for MetaTrader 5."

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
   string baseline_key=DayKey("BaselineEquity");
   string loss_lock_key=DayKey("DailyLossLocked");

   if(GlobalVariableCheck(baseline_key))
      day_start_equity=GlobalVariableGet(baseline_key);
   else
     {
      day_start_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(baseline_key,day_start_equity);
     }

   daily_loss_locked=GlobalVariableCheck(loss_lock_key) && GlobalVariableGet(loss_lock_key)>0.5;
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
      bool request_sent=trade.PositionClose(ticket);
      uint retcode=trade.ResultRetcode();
      if(request_sent && (retcode==TRADE_RETCODE_DONE || retcode==TRADE_RETCODE_DONE_PARTIAL))
         Audit("POSITION_CLOSE_SUCCESS",StringFormat("ticket=%I64u retcode=%u",ticket,retcode));
      else
         Audit("POSITION_CLOSE_FAILED",StringFormat("ticket=%I64u retcode=%u description=%s error=%d",
                                                    ticket,retcode,trade.ResultRetcodeDescription(),GetLastError()));
     }
  }

void LiquidateOnce(const string trigger,const string attempt_key)
  {
   if(!HasScopedPositions() || GlobalVariableCheck(attempt_key))
      return;
   // The marker is written before execution, preventing repeated close loops
   // even if the terminal or broker rejects one of the requests.
   GlobalVariableSet(attempt_key,(double)TimeTradeServer());
   CloseScopedPositions(trigger);
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
      GlobalVariableSet(DayKey("DailyLossLocked"),1.0);
      Audit("DAILY_LOSS_BREACHED",StringFormat("loss=%.2f%% limit=%.2f%%",daily_loss_percent,MaxDailyLossPercent));
     }
   if(daily_loss_locked)
     {
      AddViolation("MAX_DAILY_LOSS");
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
      LiquidateOnce("EMERGENCY_STOP",global_prefix+".EmergencyCloseAttempt");
   else if(!EmergencyStop)
      GlobalVariableDel(global_prefix+".EmergencyCloseAttempt");
   if(daily_loss_locked && ClosePositionsOnDailyLossBreach)
      LiquidateOnce("MAX_DAILY_LOSS",DayKey("DailyLossCloseAttempt"));

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

int OnInit()
  {
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   global_prefix=StringFormat("RiskGuard.%I64d.%I64d",AccountInfoInteger(ACCOUNT_LOGIN),MagicNumberFilter);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);
   LoadTradingDay(true);
   EventSetTimer(1);
   Audit("RISK_GUARD_STARTED",StringFormat("scope_magic=%I64d destructive_emergency=%s destructive_daily_loss=%s",
                                          MagicNumberFilter,ClosePositionsOnEmergencyStop?"true":"false",
                                          ClosePositionsOnDailyLossBreach?"true":"false"));
   EvaluateRisk();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectDelete(0,panel_name);
   Audit("RISK_GUARD_STOPPED",IntegerToString(reason));
  }

void OnTimer()
  {
   EvaluateRisk();
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   EvaluateRisk();
  }
