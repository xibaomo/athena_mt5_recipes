//+------------------------------------------------------------------+
//|                                                          tmp.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
CSymbolInfo    m_symbol_Base;  
int OnInit()
  {
//---
   m_symbol_Base.Name("EURUSD");
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   static datetime prevBar=0;
    datetime time_0 = iTime(NULL,PERIOD_H1,0);
    if (time_0 == prevBar)
        return;
    prevBar = time_0;
    string timestr = TimeToString(time_0);
  }
//+------------------------------------------------------------------+
