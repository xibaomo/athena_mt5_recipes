//+------------------------------------------------------------------+
//|                                                      testdll.mq5 |
//|                        Copyright 2018, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2018, FXUA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#define BUFLEN  256
struct CharArray {
   char a[BUFLEN];
   char b[BUFLEN];
   char c[BUFLEN];
};
#import "athena_win_apiclient.dll"
int athena_test_dll();
int athena_init(string symbol, string hostip, string port);
int athena_send_history_minbars(double &arr[], int len, int minbar_size);
int athena_request_action(double);
int athena_register_position(ulong tk, string timestamp);
int athena_send_closed_position_info(ulong tk, string timestamp, double profit);
int athena_accumulate_minbar(string date,double open, double high, double low, double close, double tickvol);
int athena_finish();
int test_api_server(string hostip, string port);
#import

#define MAX_POS 200
#define MINBAR_SIZE 5
#define MAXTRY 2
#define SLEEP_MS 10000
#define ONE_MIN 1000*60
#define MAX_RAND 32767
#define CURRENT_PERIOD PERIOD_M15
#define MAX_ALLOWED_POS 200
#define HISTORY_LEN 1000

#define RETURN_THRESHOLD 3E-3
#define TAKE_PROFIT 100
#define STOP_LOSS -100
#define MAX_TOTAL_PROFIT 300
#define MAX_TOTAL_LOSS -1000

CPositionInfo  m_position;                   // trade position object
CTrade         m_trade;                      // trading object
CSymbolInfo    m_symbol_Base;                // symbol info object
CAccountInfo   m_account;                    // account info wrapper

//--- input parameters
string hostip    = "192.168.150.67";
//string hostip    = "127.0.0.1";
string port      = "8888";

sinput ulong  m_magic   = 2512554564564;

double lot_size_x   = 0.05;

int max_pos=0;
string timeBound = "2119.3.22 23:50";

//---
ulong m_slippage = 10;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
MqlRates lastRate;
int OnInit()
{
    Print("Connecting api server ...");
    athena_init(Symbol(),hostip,port);
    Print("Api server connected");
    
    string sym_x = Symbol();
    PrintFormat("Sym: %s",sym_x);
    PrintFormat("LR length: %d",HISTORY_LEN);
    
    if (!m_symbol_Base.Name(sym_x)) {
        PrintFormat("Failed to set symbol name: %s",sym_x);
        return (INIT_FAILED);
    }
    
    string err_text="";
    if(!CheckVolumeValue(lot_size_x,err_text)) {
        PrintFormat("Volume value check failed: %s",err_text);
        return (INIT_PARAMETERS_INCORRECT);
    }
    // send init time to api server
    MqlRates latestRate[1];
    if (CopyRates(Symbol(),CURRENT_PERIOD,1,1,latestRate) <= 0) {
        Print("Failed to get history latest min bar");
    }

    sendPastMinBars(sym_x,HISTORY_LEN);

    lot_size_x = NormalizeDouble(lot_size_x,2);

    PrintFormat("lot size: %f",lot_size_x);
        
    m_trade.SetExpertMagicNumber(m_magic);

    if(IsFillingTypeAllowed(SYMBOL_FILLING_FOK))
        m_trade.SetTypeFilling(ORDER_FILLING_FOK);
    else if(IsFillingTypeAllowed(SYMBOL_FILLING_IOC))
        m_trade.SetTypeFilling(ORDER_FILLING_IOC);
    else
        m_trade.SetTypeFilling(ORDER_FILLING_RETURN);

    m_trade.SetDeviationInPoints(m_slippage);

    return(INIT_SUCCEEDED);
}

int sendPastMinBars(string sym, int histLen)
{
    MqlRates rates[];
    ArrayResize(rates,histLen);
    if (CopyRates(sym,CURRENT_PERIOD,2,histLen,rates) <= 0) {
        Print("Failed to get history min bars");
        return -1;
    }

    int actualHistLen = histLen;
    int idx=0;
    double data[];
    ArrayResize(data,actualHistLen*MINBAR_SIZE);
    int k=0;
    for (int i=idx; i < histLen; i++) {
        data[k++] = rates[i].open;
        data[k++] = rates[i].high;
        data[k++] = rates[i].low;
        data[k++] = rates[i].close;
        data[k++] = rates[i].tick_volume;
    }

    lastRate = rates[histLen-1];
    PrintFormat("Latest bar: %f,%f,%f,%f,%f",lastRate.open,lastRate.high,lastRate.low,lastRate.close,lastRate.tick_volume);
    PrintFormat("bars to send: %d",actualHistLen);
    
    athena_send_history_minbars(data,actualHistLen,MINBAR_SIZE);
    
    string t1 = TimeToString(rates[0].time);
    string t2 = TimeToString(rates[histLen-1].time);
    PrintFormat("Min bars sent: %s to %s",t1,t2);

    ArrayFree(rates);
    ArrayFree(data);

    return actualHistLen;
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
//---
    athena_finish();
    Print("athena_finish called");
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{

    if (!m_symbol_Base.RefreshRates()) {
        Print("Failed to refresh rates\n");
        return;
    }
    if(isTestEnd()) return;

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
    
    //int action = sendMinPair(timestr,px,py,m_symbol_Hedge.Point(), m_symbol_Hedge.TickValue(),hedge_factor);
    MqlRates lastRate[1];
    if (CopyRates(Symbol(),CURRENT_PERIOD,1,1,lastRate) <= 0) {
        Print("Failed to get history latest min bar");
    }
    
    printf("Sending min pair to backend...");
    string tmstr = TimeToString(lastRate[0].time);
    athena_accumulate_minbar(tmstr,lastRate[0].open,lastRate[0].high,lastRate[0].low,lastRate[0].close,lastRate[0].tick_volume);
    
    if (nowHour == prevHour) return;
    prevHour = nowHour;
    printf("Requst decision ...");
    int action = athena_request_action(px);
    printf("Received decision from backend: %d", action);
    
    CharArray arr;
    if (action==0) {
      Print("No action");
      return;
    } 
    
    ulong tk = 0;
    if (action==1) {
      tk = OpenBuy(m_symbol_Base,lot_size_x);
      if (tk <=0) {
         PrintFormat("Failed to place buy position: %s",m_symbol_Base.Name());
      }
    }
    
    if (action==2) {
      tk = OpenSell(m_symbol_Base,lot_size_x);
      if (tk <=0) {
         PrintFormat("Failed to place buy position: %s",m_symbol_Base.Name());
      }
    }

   
   if (action==3) { // close all positions
      PrintFormat("Close all positions");
      if(PositionsTotal()>0)
         closeAllPos();
      PrintFormat("All positions closed");
   }
   if (tk > 0) {
      athena_register_position(tk,timestr);
   }

    return;
}

void OnTrade()
{
   sendLastDeal();
}

//long lastTicket=-1;
//=======================  Private functions ======================================
void sendLastDeal() {
      double last_trade_profit = 0.;
      static int previous_open_positions = 0;
        int current_open_positions = PositionsTotal();
        string ts = TimeToString(TimeCurrent());
        if(current_open_positions < previous_open_positions)    // a position just got closed. send its ticket and profit to backend
        {
                previous_open_positions = current_open_positions;
                HistorySelect(TimeCurrent()-300, TimeCurrent()); // 5 minutes ago up to now :)
                int All_Deals = HistoryDealsTotal();
                if(All_Deals < 1) Print("Some nasty shit error has occurred");
                ulong temp_Ticket = HistoryDealGetTicket(All_Deals-1); // last deal (should be an DEAL_ENTRY_OUT type)
                // here check some validity factors of the position-closing deal (symbol, position ID, even MagicNumber if you care...)
                last_trade_profit = HistoryDealGetDouble(temp_Ticket , DEAL_PROFIT);
                long ptk = HistoryDealGetInteger(temp_Ticket,DEAL_POSITION_ID);
                PrintFormat("position closed. profit: %.2f",last_trade_profit);
                                
                athena_send_closed_position_info(ptk,ts,last_trade_profit);
        }
        else if(current_open_positions > previous_open_positions) {
            previous_open_positions = current_open_positions; // a position just got opened.
            HistorySelect(TimeCurrent()-300, TimeCurrent()); // 5 minutes ago up to now :)
                int All_Deals = HistoryDealsTotal();
                if(All_Deals < 1) Print("Some nasty shit error has occurred");
                ulong temp_Ticket = HistoryDealGetTicket(All_Deals-1);
            //registerPosition(temp_Ticket,ts);
        }
}
void closePos(long tk) {
   while(m_position.SelectByTicket(tk)) {
      m_trade.PositionClose(tk);
   }
}

int getHour(datetime time0) {
   MqlDateTime mqt;
   TimeToStruct(time0,mqt);
   return mqt.hour;
}
//+------------------------------------------------------------------+
//| Refreshes the symbol quotes data                                 |
//+------------------------------------------------------------------+
bool RefreshRates(CSymbolInfo &m_symbol)
{
//--- refresh rates
    if(!m_symbol.RefreshRates()) {
        Print("RefreshRates error");
        return(false);
    }
//--- protection against the return value of "zero"
    if(m_symbol.Ask()==0 || m_symbol.Bid()==0)
        return(false);
//---
    return(true);
}
//+------------------------------------------------------------------+
//| Checks if the specified filling mode is allowed                  |
//+------------------------------------------------------------------+
bool IsFillingTypeAllowed(int fill_type)
{
//--- Obtain the value of the property that describes allowed filling modes
    int filling=m_symbol_Base.TradeFillFlags();
//--- Return true, if mode fill_type is allowed
    return((filling & fill_type)==fill_type);
}
//+------------------------------------------------------------------+
//| Check the correctness of the order volume                        |
//+------------------------------------------------------------------+
bool CheckVolumeValue(double volume,string &error_description)
{
//--- minimal allowed volume for trade operations
    double min_volume=m_symbol_Base.LotsMin();
    if(volume<min_volume) {
        error_description=StringFormat("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=%.2f",min_volume);
        return(false);
    }
//--- maximal allowed volume of trade operations
    double max_volume=m_symbol_Base.LotsMax();
    if(volume>max_volume) {
        error_description=StringFormat("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=%.2f",max_volume);
        return(false);
    }
//--- get minimal step of volume changing
    double volume_step=m_symbol_Base.LotsStep();
    int ratio=(int)MathRound(volume/volume_step);
    if(MathAbs(ratio*volume_step-volume)>0.0000001) {
        error_description=StringFormat("Volume is not a multiple of the minimal step SYMBOL_VOLUME_STEP=%.2f, the closest correct volume is %.2f",
                                       volume_step,ratio*volume_step);
        return(false);
    }
    error_description="Correct volume value";
    return(true);
}

//+------------------------------------------------------------------+
//| Open Buy position                                                |
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
                        PrintResult(m_trade,symbol);
                    } else {
                        Print("#2 Buy -> true. Result Retcode: ",m_trade.ResultRetcode(),
                              ", description of result: ",m_trade.ResultRetcodeDescription());
                        PrintResult(m_trade,symbol);
                        return m_trade.ResultOrder();
                        break;
                    }
                }

                else {
                    Print("#3 Buy -> false. Result Retcode: ",m_trade.ResultRetcode(),
                          ", description of result: ",m_trade.ResultRetcodeDescription());
                    PrintResult(m_trade,symbol);
                }
                Sleep(SLEEP_MS);
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
                        PrintResult(m_trade,symbol);
                    } else {
                        Print("#2 Sell -> true. Result Retcode: ",m_trade.ResultRetcode(),
                              ", description of result: ",m_trade.ResultRetcodeDescription());
                        PrintResult(m_trade,symbol);
                        return m_trade.ResultOrder();
                        break;
                    }
                } else {
                    Print("#3 Sell -> false. Result Retcode: ",m_trade.ResultRetcode(),
                          ", description of result: ",m_trade.ResultRetcodeDescription());
                    PrintResult(m_trade,symbol);
                }
                Sleep(SLEEP_MS);
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

//+------------------------------------------------------------------+
//| Print CTrade result                                              |
//+------------------------------------------------------------------+
void PrintResult(CTrade &trade,CSymbolInfo &symbol)
{
    Print("Code of request result: "+IntegerToString(trade.ResultRetcode()));
    Print("code of request result: "+trade.ResultRetcodeDescription());
    Print("deal ticket: "+IntegerToString(trade.ResultDeal()));
    Print("order ticket: "+IntegerToString(trade.ResultOrder()));
    Print("volume of deal or order: "+DoubleToString(trade.ResultVolume(),2));
    Print("price, confirmed by broker: "+DoubleToString(trade.ResultPrice(),symbol.Digits()));
    Print("current bid price: "+DoubleToString(trade.ResultBid(),symbol.Digits()));
    Print("current ask price: "+DoubleToString(trade.ResultAsk(),symbol.Digits()));
    Print("broker comment: "+trade.ResultComment());
    //DebugBreak();
}
//+------------------------------------------------------------------+

void closeMostProfitPos()
{
   double max_profit = 0.;
   int ticket = -1;
   for (int i = PositionsTotal()-1; i>=0; i--) {
      if (m_position.SelectByIndex(i)) {
         if (m_position.Profit() > max_pos) {
            max_profit = m_position.Profit();
            ticket = m_position.Ticket();
         }
      }
   }
   if (ticket >= 0) {
      m_trade.PositionClose(ticket);
      PrintFormat("Position closed. Profit: %f, ticket %d",max_profit,ticket);
   }
}
//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void closeAllPos()
{
   int ticket = -1;
   while (PositionsTotal()>0) {
      for (int i = PositionsTotal()-1; i>=0; i--) {
         if (m_position.SelectByIndex(i)) {
               ticket = m_position.Ticket();
               m_trade.PositionClose(ticket);
         }
      }
   }
}
//+------------------------------------------------------------------+
//| Close buy y positions                                            |
//+------------------------------------------------------------------+
bool isHavePosType(ENUM_POSITION_TYPE type) {
   CPositionInfo pos;
   for (int i = 0; i < PositionsTotal(); i++) {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.PositionType()==type) return true;
   }
   return false;
}

void inspectAllPositions(CSymbolInfo& symbol)
{
   PrintFormat("Inspect all positions: %d",PositionsTotal());
   MqlTick last_tick;
   float ask,bid;
   if (SymbolInfoTick(symbol.Name(),last_tick)) {
      ask = last_tick.ask;
      bid = last_tick.bid;
   }
   Print("last tick obtained");
   for (int i = PositionsTotal()-1;i >=0; i++) {
      if (m_position.SelectByIndex(i)) {
         
         if (m_position.Symbol() != symbol.Name()) continue;
         PrintFormat("%s,%s",m_position.Symbol(),symbol.Name());
         
         if (m_position.PositionType() == POSITION_TYPE_BUY && bid > 0.) {
            PrintFormat("check buy position, bid: %f",bid);
            
            if (m_position.TakeProfit() <= bid || m_position.StopLoss() >= bid) {
               m_trade.PositionClose(m_position.Ticket());
               PrintFormat("Position closed: %d",m_position.Ticket());
            }
            Print("check buy position done");
         }
         if (m_position.PositionType() == POSITION_TYPE_SELL && ask > 0.) {
            PrintFormat("Check sell position, ask: %f",ask);
            if (m_position.TakeProfit() >= ask || m_position.StopLoss() <= ask) {
               m_trade.PositionClose(m_position.Ticket());
               PrintFormat("Position closed: %d",m_position.Ticket());
            }
            Print("check sell position done");
         }
      }
   }
}

bool isTestEnd()
{
   datetime t_current = TimeCurrent();
   datetime time_bound = StringToTime(timeBound);
   if (t_current - time_bound >=0)
      return true;
      
   return false;
}

 double getExRate(const string tar) {
   if(tar=="USD") return 1.f;
   string sym_name;
   StringConcatenate(sym_name,tar,"USD");
   CSymbolInfo sym;
   if(sym.Name(sym_name)) {
      sym.RefreshRates();
      double mid = sym.Ask() + sym.Bid();
      return mid*.5;
   }
   
   StringConcatenate(sym_name,"USD",tar);
   if(sym.Name(sym_name)) {
      sym.RefreshRates();
      double mid = sym.Ask() + sym.Bid();
      return 2./sym.Ask();
   }
   
   printf("no exchange rate found for %s",tar);
   return -1;
 } 
 
