//+------------------------------------------------------------------+
//|                                                  test_margin.mq5 |
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
int OnInit()
  {
//---
CSymbolInfo sym_x,sym_y,sym;
   string x_name = "USDDKK";
   string y_name = "EURUSD";
   sym_x.Name(x_name);
   sym_y.Name(y_name);
   
   printf("%s",sym_x.CurrencyBase());
   printf("%s",sym_x.CurrencyMargin());
   printf("%s",sym_x.CurrencyProfit());
   
   
   sym = sym_x;
   double pt = sym.Point();
   int dg = sym.Digits();
   double tk = sym.TickValue();
   double tksz = sym.TickSize();
   double tkp = sym.TickValueProfit();
   double tkl = sym.TickValueLoss();
   sym.RefreshRates();
   double total_ask = sym.Ask()/sym.TickSize()*sym.TickValue();
   double total_bid = sym.Bid()/sym.TickSize()*sym.TickValue();
//---

   double er = getExRate(sym_y.CurrencyMargin());
   printf("exchange rate of %s: %f",sym_y.CurrencyMargin(),er);
   return(INIT_SUCCEEDED);
  }
  
 double getExRate(const string tar) {
   if(tar=="USD") return 1.f;
   string sym_name;
   StringConcatenate(sym_name,tar,"USD");
   CSymbolInfo sym;
   if(sym.Name(sym_name)) {
      sym.RefreshRates();
      return sym.Ask();
   }
   
   StringConcatenate(sym_name,"USD",tar);
   if(sym.Name(sym_name)) {
      sym.RefreshRates();
      return 1./sym.Ask();
   }
   
   printf("no exchange rate found for %s",tar);
   return -1;
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
   
  }
//+------------------------------------------------------------------+
