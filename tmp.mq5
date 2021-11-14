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
#define RETURN_THRESHOLD 3E-3
#define CURRENT_PERIOD PERIOD_M15
#define MAXTRY 2

CPositionInfo  m_position;                   // trade position object
CTrade         m_trade;                      // trading object
CSymbolInfo    m_symbol_Base;                // symbol info object
CAccountInfo   m_account;

int count= 0;
string timeBound = "2021.10.12 23:50";
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   m_symbol_Base.Name("USDDKK");
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
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
  {
//---
      double last_trade_profit = 0.;
      static int previous_open_positions = 0;
        int current_open_positions = PositionsTotal();
        if(current_open_positions < previous_open_positions)    // a position just got closed.
        {
                previous_open_positions = current_open_positions;
                HistorySelect(TimeCurrent()-300, TimeCurrent()); // 5 minutes ago up to now :)
                int All_Deals = HistoryDealsTotal();
                if(All_Deals < 1) Print("Some nasty shit error has occurred");
                ulong temp_Ticket = HistoryDealGetTicket(All_Deals-1); // last deal (should be an DEAL_ENTRY_OUT type)
                // here check some validity factors of the position-closing deal (symbol, position ID, even MagicNumber if you care...)
                last_trade_profit = HistoryDealGetDouble(temp_Ticket , DEAL_PROFIT);
                PrintFormat("position closed. profit: %.2f",last_trade_profit);
        }
        else if(current_open_positions > previous_open_positions) previous_open_positions = current_open_positions; // a position just got opened.
  }
  //+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {
//---
datetime time_0 = iTime(NULL,CURRENT_PERIOD,0);
   Print("trade transac happens");
   //if (trans.order != trans.position) {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if((int)trans.deal_type != (int)trans.order_type){
      ulong tk = trans.deal;
      double profit = HistoryDealGetDouble(tk,DEAL_PROFIT);
      PrintFormat("position closed. profit: %.2f",profit);
   }
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
     if (!m_symbol_Base.RefreshRates()) {
        Print("Failed to refresh rates\n");
        return;
    }
    
    if(isTestEnd()) return;
    
    //updateMinMaxPairProfit();

    static datetime prevBar=0;
    static int prevHour = -1;   // previous hour
    datetime time_0 = iTime(NULL,CURRENT_PERIOD,0);
    if (time_0 == prevBar)
        return;
    prevBar = time_0;
    string timestr = TimeToString(time_0);
    int nowHour = getHour(time_0);

   float x_ask = m_symbol_Base.Ask();
   float x_bid = m_symbol_Base.Bid();
   float x_spread = m_symbol_Base.Spread();

    float px = (m_symbol_Base.Ask()+m_symbol_Base.Bid())*.5;
    //PrintFormat("%s, %s open: %f",timestr,sym_x,px);
    
    //int action = sendMinPair(timestr,px,py,m_symbol_Hedge.Point(), m_symbol_Hedge.TickValue(),hedge_factor);
    
    MqlRates lastRate[10];
    if (CopyRates(Symbol(),CURRENT_PERIOD,2,10,lastRate) <= 0) {
        Print("Failed to get history latest min bar");
    }
    
    printf("Sending min pair to backend...");
    string tmstr = TimeToString(lastRate[0].time);
    PrintFormat("%s",tmstr);
    printf("Sending min pair to backend...");
    //accumulateMinBar(lastRate[0].open,lastRate[0].high,lastRate[0].low,lastRate[0].close,lastRate[0].tick_volume,px,timestr);
    
    if (nowHour == prevHour) return;
    prevHour = nowHour;
    //if (count % 2 == 1)
      OpenBuy(m_symbol_Base,0.1);
      //else 
      //OpenSell(m_symbol_Base,0.1);


   count++;
  }
//+------------------------------------------------------------------+
long OpenBuy(CSymbolInfo &symbol, double lotsize, string cmt="")
{
    double check_open_long_lot=lotsize;
//--- check volume before OrderSend to avoid "not enough money" error (CTrade)
    double check_volume_lot=m_trade.CheckVolume(symbol.Name(),check_open_long_lot,symbol.Ask(),ORDER_TYPE_BUY);

    int digits = (int)SymbolInfoInteger(symbol.Name(),SYMBOL_DIGITS);
    double price = symbol.Ask();
    double tp = NormalizeDouble(price + RETURN_THRESHOLD*price,digits);
    double sl = NormalizeDouble(price - RETURN_THRESHOLD*price,digits);
    

    if(check_volume_lot!=0.0) {
        if(check_volume_lot>=check_open_long_lot) {
            for (int i=0; i < MAXTRY; i++) {
                PrintFormat("Try buy: %dth",i);
                symbol.RefreshRates();
                if(m_trade.Buy(check_open_long_lot,symbol.Name(),symbol.Ask(),sl,tp,cmt)) {

                    if(m_trade.ResultDeal()==0) {
                        Print("#1 Buy -> false. Result Retcode: ",m_trade.ResultRetcode(),
                              ", description of result: ",m_trade.ResultRetcodeDescription());
                        //PrintResult(m_trade,symbol);
                    } else {
                        Print("#2 Buy -> true. Result Retcode: ",m_trade.ResultRetcode(),
                              ", description of result: ",m_trade.ResultRetcodeDescription());
                        //PrintResult(m_trade,symbol);
                        return m_trade.ResultOrder();
                        break;
                    }
                }

                else {
                    Print("#3 Buy -> false. Result Retcode: ",m_trade.ResultRetcode(),
                          ", description of result: ",m_trade.ResultRetcodeDescription());
                    //PrintResult(m_trade,symbol);
                }
                //Sleep(SLEEP_MS);
            }
        } else {
            Print(__FUNCTION__,", ERROR: method CheckVolume (",DoubleToString(check_volume_lot,2),") ",
                  "< \"Lots\" (",DoubleToString(check_open_long_lot,2),")");
            return -1;
        }
    } else {
        Print(__FUNCTION__,", ERROR: method CheckVolume returned the value of \"0.0\"");
        return -1;
    }
//---r
   return -1;
}
int getHour(datetime time0) {
   MqlDateTime mqt;
   TimeToStruct(time0,mqt);
   return mqt.hour;
}

//+------------------------------------------------------------------+
//| Open Sell position                                               |
//+------------------------------------------------------------------+
long OpenSell(CSymbolInfo &symbol,double lotsize, string cmt="")
{
    double check_open_short_lot=lotsize;
//--- check volume before OrderSend to avoid "not enough money" error (CTrade)
    double check_volume_lot=m_trade.CheckVolume(symbol.Name(),check_open_short_lot,symbol.Bid(),ORDER_TYPE_SELL);

    int digits = (int)SymbolInfoInteger(symbol.Name(),SYMBOL_DIGITS);
    double price = symbol.Bid();
    double pv = SymbolInfoDouble(symbol.Name(),SYMBOL_TRADE_TICK_VALUE) * SymbolInfoDouble(symbol.Name(),SYMBOL_POINT);
    double tp = NormalizeDouble(price - RETURN_THRESHOLD*price,digits);
    double sl = NormalizeDouble(price + RETURN_THRESHOLD*price,digits);

    if(check_volume_lot!=0.0) {
        if(check_volume_lot>=check_open_short_lot) {
            for (int i=0; i < MAXTRY; i++) {
                PrintFormat("Try sell: %dth",i);
                symbol.RefreshRates();
                if(m_trade.Sell(check_open_short_lot,symbol.Name(),symbol.Bid(),sl,tp,cmt)) {

                    if(m_trade.ResultDeal()==0) {
                        Print("#1 Sell -> false. Result Retcode: ",m_trade.ResultRetcode(),
                              ", description of result: ",m_trade.ResultRetcodeDescription());
                        //PrintResult(m_trade,symbol);
                    } else {
                        Print("#2 Sell -> true. Result Retcode: ",m_trade.ResultRetcode(),
                              ", description of result: ",m_trade.ResultRetcodeDescription());
                        //PrintResult(m_trade,symbol);
                        return m_trade.ResultOrder();
                        break;
                    }
                } else {
                    Print("#3 Sell -> false. Result Retcode: ",m_trade.ResultRetcode(),
                          ", description of result: ",m_trade.ResultRetcodeDescription());
                    //PrintResult(m_trade,symbol);
                }
                //Sleep(SLEEP_MS);
            }
        } else {
            Print(__FUNCTION__,", ERROR: method CheckVolume (",DoubleToString(check_volume_lot,2),") ",
                  "< \"Lots\" (",DoubleToString(check_open_short_lot,2),")");
            return -1;
        }
    } else {
        Print(__FUNCTION__,", ERROR: method CheckVolume returned the value of \"0.0\"");
        return -1;
    }
//---
   return -1;
}
bool isTestEnd()
{
   datetime t_current = TimeCurrent();
   datetime time_bound = StringToTime(timeBound);
   if (t_current - time_bound >=0)
      return true;
      
   return false;
}