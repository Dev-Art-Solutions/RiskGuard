//+------------------------------------------------------------------+
//| RiskGuard.mq5                                                     |
//| Strategy-agnostic account risk monitoring and enforcement for     |
//| MetaTrader 5.                                                     |
//+------------------------------------------------------------------+
#property copyright "Dev Art Solutions"
#property link      "https://devart.solutions"
#property version   "1.00"
#property strict
#property description "Strategy-agnostic account risk monitoring and enforcement for MetaTrader 5."

#include "RiskGuardCore.mqh"

int OnInit()
  {
   int result=RiskGuardInit();
   if(result!=INIT_SUCCEEDED)
      return result;
   RiskGuardEmitInitialState();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   RiskGuardDeinit(reason);
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
