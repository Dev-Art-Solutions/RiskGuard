//+------------------------------------------------------------------+
//| RiskGuardTestHarness.mq5                                          |
//| TEST-ONLY tool. Not part of the shipped product.                  |
//|                                                                    |
//| MT5's Strategy Tester runs exactly one Expert Advisor per test,    |
//| and RiskGuard itself never opens trades -- it only reacts to      |
//| positions that already exist. This harness opens a configurable   |
//| number of synthetic positions at start-up (before the first risk  |
//| evaluation) and then runs the exact same RiskGuardCore logic the  |
//| production EA runs, so position-dependent scenarios in            |
//| docs/TEST_PLAN.md (TRADE-*, POS-*, RISK-*, SCOPE-*, STATE-01) can  |
//| be exercised headlessly via the command-line Strategy Tester.     |
//|                                                                    |
//| Never attach this to a live or demo chart outside Strategy Tester. |
//+------------------------------------------------------------------+
#property copyright "Dev Art Solutions"
#property link      "https://devart.solutions"
#property version   "1.00"
#property strict
#property description "TEST-ONLY harness: opens synthetic positions, then runs RiskGuard's risk evaluation. Strategy Tester use only."

#include "../src/RiskGuardCore.mqh"

input group "Harness (synthetic positions -- test tool only)"
input int    HarnessOpenPositionsCount = 1;     // number of synthetic positions to open at start
input double HarnessVolume             = 0.10;  // lots per synthetic position
input int    HarnessSLDistancePoints   = 200;   // 0 = open without a stop-loss (RISK-03 / RISK-04)
input long   HarnessTradeMagic         = 0;     // magic number stamped on synthetic positions (SCOPE-01 / SCOPE-02)
input bool   HarnessSell               = false; // open SELL instead of BUY

CTrade harness_trade;

void OpenSyntheticPositions()
  {
   harness_trade.SetAsyncMode(false);
   harness_trade.SetExpertMagicNumber((ulong)HarnessTradeMagic);

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   for(int index=0; index<HarnessOpenPositionsCount; ++index)
     {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double stop_loss=0.0;
      bool sent;

      if(HarnessSell)
        {
         if(HarnessSLDistancePoints>0)
            stop_loss=bid+HarnessSLDistancePoints*point;
         sent=harness_trade.Sell(HarnessVolume,_Symbol,bid,stop_loss,0.0,"harness");
        }
      else
        {
         if(HarnessSLDistancePoints>0)
            stop_loss=ask-HarnessSLDistancePoints*point;
         sent=harness_trade.Buy(HarnessVolume,_Symbol,ask,stop_loss,0.0,"harness");
        }

      if(!sent)
         Audit("HARNESS_OPEN_FAILED",StringFormat("index=%d retcode=%u description=%s",
                                                  index,harness_trade.ResultRetcode(),
                                                  harness_trade.ResultRetcodeDescription()));
      else
         Audit("HARNESS_OPEN_SUCCESS",StringFormat("index=%d ticket=%I64u magic=%I64d sl_points=%d",
                                                   index,harness_trade.ResultOrder(),HarnessTradeMagic,
                                                   HarnessSLDistancePoints));
     }
  }

int OnInit()
  {
   int result=RiskGuardInit();
   if(result!=INIT_SUCCEEDED)
      return result;

   OpenSyntheticPositions();
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
