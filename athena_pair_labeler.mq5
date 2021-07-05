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
int athena_init(string symbol, string hostip, string port);
//int sendHistoryTicks(float &arr[], int len, string pos_type);
//int sendHistoryMinBars(float &arr[], int len, int minbar_size);
string sendInitTime(string timeString);
int askSymPair(CharArray& arr);
int sendPairHistX(float &arr[], int len, int n_pts,double tick_size, double tickval);
float sendPairHistY(float &arr[], int len, int n_pts, double tick_size, double tick_val);
int sendMinPair(string timestr, double x_ask, double x_bid, double ticksize_x, double tickval_x, double y_ask, double y_bid, double ticksize_y, double tickval_x, int npos, int ntp, int nsl, double& hf);
int sendMinPairLabel(int id, int label);
//int classifyAMinBar(float open,float high, float low, float close, float tickvol, string timeString);
int registerPairStr(CharArray& arr, bool isSend);
int sendPairProfitStr(CharArray& arr, float profit);
int getPairedTicketStr(CharArray& arr); // arr.a is tx, arr.b is ty
int sendCurrentProfit(float profit);
int sendPositionProfit(float profit);
int sendSymbolHistory(float &arr[],int len, string sym);
int athena_finish();
int test_api_server(string hostip, string port);
#import

#define MAX_POS 200
#define MINBAR_SIZE 5
#define MAXTRY 2
#define SLEEP_MS 10000
#define ONE_MIN 1000*60
#define MAX_RAND 32767
#define CURRENT_PERIOD PERIOD_M5
#define STOP_PERCENT 0.05
#define MAX_ALLOWED_POS 2000000
#define HISTORY_LEN 2000

#define TAKE_PROFIT 2
#define STOP_LOSS -10
#define MAX_TOTAL_PROFIT 300
#define MAX_TOTAL_LOSS -1000
//--- special fix for a mql4 bug (ME 934)
class CFix { } ExtFix;
CPositionInfo  m_position;                   // trade position object
CTrade         m_trade;                      // trading object
CSymbolInfo    m_symbol_Base;                // symbol info object
CSymbolInfo    m_symbol_Hedge;               // symbol info object
CAccountInfo   m_account;                    // account info wrapper

//--- input parameters
string hostip    = "192.168.1.103";
string port      = "8888";

sinput ulong  m_magic   = 2512554564564;
string              sym_x                = "EURUSD";
string              sym_y                = "USDCZK";

int    buy_tp = 2000;
int    buy_sl  = buy_tp;
int    sell_tp = buy_tp;
int    sell_sl = buy_sl;
double lot_size_x   = 0.05;
double lot_size_y = lot_size_x;
float sym_pv_ratio;
double hedge_factor;
double InpVirtualProfit = 5000.0;
int max_pos=0;
string timeBound = "2119.3.22 23:50";

int g_posPrev = 0;
int g_minbarCount = 0;
double g_maxPairProfit = -100000;
double g_minPairProfit = 100000;
int g_ntp = 0;
int g_nsl = 0;
//---
ulong m_slippage = 10;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
MqlRates lastRate;
int OnInit()
{
    registerCurrentPositions();
    checkPairProfit();
    
    Print("Connecting api server ...");
    athena_init(Symbol(),hostip,port);
    Print("Api server connected");
    
    g_posPrev = PositionsTotal();  
    
    //string symPair = selectPair(); 
    CharArray arr;
    askSymPair(arr);
    
    string symPair = CharArrayToString(arr.a);
    
    sym_x = StringSubstr(symPair,0,6);
    sym_y = StringSubstr(symPair,7,6);
    PrintFormat("Sym x: %s, Sym y: %s",sym_x,sym_y);
    PrintFormat("LR length: %d",HISTORY_LEN);
    
    if (!m_symbol_Base.Name(sym_x)) {
        PrintFormat("Failed to set symbol name: %s",sym_x);
        return (INIT_FAILED);
    }
    if (!m_symbol_Hedge.Name(sym_y)) {
      PrintFormat("Failed to set symbol name: %s",sym_y);
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

    sendPastMinBars(sym_x,HISTORY_LEN,"x");
    sendPastMinBars(sym_y,HISTORY_LEN,"y");
        
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

int sendPastMinBars(string sym, int histLen, string xy)
{
    MqlRates rates[];
    ArrayResize(rates,histLen);
    if (CopyRates(sym,CURRENT_PERIOD,1,histLen,rates) <= 0) {
        Print("Failed to get history min bars");
        return -1;
    }

    int actualHistLen = histLen;
    int idx=0;
    float data[];
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
    
    if (xy == "x")
      sendPairHistX(data,actualHistLen,MINBAR_SIZE,m_symbol_Base.TickSize(),m_symbol_Base.TickValue());
    if (xy == "y")
      hedge_factor = sendPairHistY(data,actualHistLen,MINBAR_SIZE,m_symbol_Hedge.TickSize(),m_symbol_Hedge.TickValue());

    string t1 = TimeToString(rates[idx+1].time);
    string t2 = TimeToString(rates[histLen-1].time);
    PrintFormat("Min bars sent: %s to %s",t1,t2);
    
    PrintFormat("Hedge factor: %f",hedge_factor);

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
   printf("Pair profit, max: %f, min: %f",g_maxPairProfit, g_minPairProfit);
    athena_finish();
    Print("athena_finish called");
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{

//---
    checkPairProfit();
    if (!m_symbol_Base.RefreshRates() || !m_symbol_Hedge.RefreshRates()) {
        Print("Failed to refresh rates\n");
        return;
    }
    if(isTestEnd()) return;
    
    updateMinMaxPairProfit();

    static datetime prevBar=0;
    datetime time_0 = iTime(NULL,CURRENT_PERIOD,0);
    if (time_0 == prevBar)
        return;
    prevBar = time_0;
    string timestr = TimeToString(time_0);
    
    //float pft = IsProfit();//---
    
   // sendCurrentProfit(pft);
   g_minbarCount++;

   float x_ask = m_symbol_Base.Ask();
   float x_bid = m_symbol_Base.Bid();
   float x_spread = m_symbol_Base.Spread();
   float y_ask = m_symbol_Hedge.Ask();
   float y_bid = m_symbol_Hedge.Bid();
   float y_spread = m_symbol_Hedge.Spread();
    float px = (m_symbol_Base.Ask()+m_symbol_Base.Bid())*.5;
    float py = (m_symbol_Hedge.Ask()+m_symbol_Hedge.Bid())*.5;
    PrintFormat("%s, %s open: %f",timestr,sym_x,px);
    PrintFormat("%s, %s open: %f",timestr,sym_y,py);
    
    //int action = sendMinPair(timestr,px,py,m_symbol_Hedge.Point(), m_symbol_Hedge.TickValue(),hedge_factor);
    double tkx = m_symbol_Base.TickValue();
    double tky = m_symbol_Hedge.TickValue();
    int action = sendMinPair(timestr,x_ask,x_bid,m_symbol_Base.TickSize(), m_symbol_Base.TickValue(), y_ask,y_bid,m_symbol_Hedge.TickSize(), m_symbol_Hedge.TickValue(), 
                 PositionsTotal(),g_ntp,g_nsl,hedge_factor);
    
    double tmp = 1/fabs(hedge_factor)*lot_size_x;
    tmp*=1.2;
    lot_size_y = NormalizeDouble(tmp,2);  
    PrintFormat("Lot y: %f",lot_size_y);

    CharArray arr;
    action =2;
    if (action ==2) {
      if (PositionsTotal()>=MAX_ALLOWED_POS-2) return;
      //PrintFormat("Buy at %f",m_symbol_Base.Ask());
      long tx;
      if (hedge_factor > 0) {
         tx = OpenBuy(m_symbol_Base,lot_size_x);
      } else {
         tx = OpenSell(m_symbol_Base,lot_size_x);
      }
      if (tx <= 0) {
         PrintFormat("Failed to place buy postion: %s",m_symbol_Base.Name());
         return;
      }
      
      //long ty = OpenBuy(m_symbol_Hedge,lot_size_y,IntegerToString(tx));
      long ty = OpenSell(m_symbol_Hedge,lot_size_y,IntegerToString(g_minbarCount));
      if (ty <= 0) {
         PrintFormat("Failed to place buy postion: %s",m_symbol_Hedge.Name());
         closePos(tx);
         return;
      }
      PrintFormat("pair tickets: %d vs %d\n",tx,ty);

      registerPair(tx,ty,true);
   }
   
   //action =1;
   if (action ==1) {
      if (PositionsTotal()>=MAX_ALLOWED_POS-2) return;
      //PrintFormat("Sell at %f",m_symbol_Base.Bid());
      long tx;
      if (hedge_factor > 0) {
         tx = OpenSell(m_symbol_Base,lot_size_x);
      } else {
         tx = OpenBuy(m_symbol_Base,lot_size_x);
      }
      
      if (tx <= 0) {
         PrintFormat("Failed to place sell postion: %s",m_symbol_Base.Name());
         return;
      }

      //long ty = OpenSell(m_symbol_Hedge,lot_size_y,IntegerToString(tx));
      long ty = OpenBuy(m_symbol_Hedge,lot_size_y,IntegerToString(g_minbarCount));
      
      if (ty <= 0) {
         PrintFormat("Failed to place sell postion: %s",m_symbol_Hedge.Name());
         closePos(tx);
         return;
      }
      PrintFormat("pair tickets: %d vs %d\n",tx,ty);
      registerPair(tx,ty,true);
   }
   
   if (action==3) { // close all positions
      PrintFormat("Close all positions");
      if(PositionsTotal()>0)
         closeAllPos();
      PrintFormat("All positions closed");
   }
   if (action == 4 ) {
      //if(isHavePosType(POSITION_TYPE_BUY))
        //closeTypeYPairs(POSITION_TYPE_BUY);
   }
   if (action == 5) {
     //if(isHavePosType(POSITION_TYPE_SELL))
         //closeTypeYPairs(POSITION_TYPE_SELL);
   }
 
    return;
}

void OnTrade()
{
   HistorySelect(0,TimeCurrent());
   Print("order placed");
   int posCurr = PositionsTotal();
   if (posCurr >= g_posPrev) {
    g_posPrev = posCurr;
    return; // new position created
   }
   
   sendLastProfit();
}

long lastTicket=-1;
//=======================  Private functions ======================================

void sendSymHist(string sym, int histLen)
{
    MqlRates rates[];
    ArrayResize(rates,histLen);
    if (CopyRates(sym,CURRENT_PERIOD,1,histLen,rates) <= 0) {
        Print("Failed to get history min bars");
        return;
    }

    int actualHistLen = histLen;
    int idx=0;
    float data[];
    ArrayResize(data,actualHistLen*1);
    int k=0;
    for (int i=idx; i < histLen; i++) {
        data[k++] = rates[i].open;
    }
    
    sendSymbolHistory(data,histLen,sym);

    ArrayFree(rates);
    ArrayFree(data);
}
void registerCurrentPositions()
{
   for(int i=0; i < PositionsTotal(); i++) {
      if (!m_position.SelectByIndex(i)) continue;
      long tx = m_position.Ticket();

      long idx = m_position.Identifier();
      string sty = m_position.Comment();
      if (sty == "") continue;
      long idy = StringToInteger(sty);
      
      if(idy <=0) Alert("Weird ticket");
      registerPair(idx,idy,false);
   }
}

void registerPair(long tx, long ty, bool isSend)
{
      CharArray arr;
      string stmp = IntegerToString(tx);
      StringToCharArray(stmp,arr.a);
      stmp = IntegerToString(ty);
      StringToCharArray(stmp,arr.b);
      registerPairStr(arr,isSend);
}

long getPairedTicket(long tx)
{
   string stx = IntegerToString(tx);
   CharArray arr;
   StringToCharArray(stx,arr.a);
   getPairedTicketStr(arr);
   string sty = CharArrayToString(arr.b);
   long ty = StringToInteger(sty);
   
   //PrintFormat("paired ticket: %d",ty);
   
   return ty;
}
void checkPairProfit()
{
   double totalProf=0.; 
   for (int i=PositionsTotal(); i >= 0;i--) {
      double px=0.,py=0.;
      long tx,ty;
      if(!m_position.SelectByIndex(i)) continue;
      string cmt = m_position.Comment();
      if(cmt==NULL || cmt == "") { // pos x
         tx = m_position.Ticket();
         ty = getPairedTicket(tx);
         if(ty<0 || !m_position.SelectByTicket(ty)) {closePos(tx);continue;}
         
         m_position.SelectByTicket(tx);
         px = m_position.Profit() + m_position.Commission() + m_position.Swap();
         totalProf+=px;
         m_position.SelectByTicket(ty);
         py = m_position.Profit() + m_position.Commission() + m_position.Swap();
         totalProf+=py;
   
         if (px+py >= TAKE_PROFIT || px+py <= STOP_LOSS) {
            m_position.SelectByTicket(ty);
            string sid = m_position.Comment();
            int id = StringToInteger(sid);
            int label = -1;
            ENUM_POSITION_TYPE type = m_position.PositionType();
            if (type==POSITION_TYPE_BUY && px+py>0) {
               label = 0;
            }
            if (type==POSITION_TYPE_BUY && px+py < 0) {
               label = 1;
            }
            if (type==POSITION_TYPE_SELL && px+ py > 0) {
               label = 2;
            }
            if (type==POSITION_TYPE_SELL && px + py < 0) {
               label = 3;
            }
            sendMinPairLabel(id,label);
         
         
            PrintFormat("Take profit: %f, closing postion pair",px+py); 
            while(m_position.SelectByTicket(tx))
               m_trade.PositionClose(tx);
            while(m_position.SelectByTicket(ty))
               m_trade.PositionClose(ty);
               
            if (px+py>0) g_ntp++;
            if (px+py<0) g_nsl++;
         }
         
      } else { // pos y
         ty = m_position.Ticket();
         tx = getPairedTicket(ty);
         if(tx<0 || !m_position.SelectByTicket(tx)) closePos(ty);
      }
   }
   if (totalProf >= MAX_TOTAL_PROFIT || totalProf <= MAX_TOTAL_LOSS) {
      closeAllPos();
   }
}

void closePos(long tk) {
   while(m_position.SelectByTicket(tk)) {
      m_trade.PositionClose(tk);
   }
}

long reversePosition(long tk, string cmt="")
{
   CSymbolInfo sym;
   m_position.SelectByTicket(tk);
   sym.Name(m_position.Symbol());
   sym.RefreshRates();
   double lot = m_position.Volume();
   long tk_new=0;
   if (m_position.PositionType()==POSITION_TYPE_BUY) {
      m_trade.PositionClose(tk);
      //Sleep(ONE_MIN);
      tk_new = OpenSell(sym,lot,cmt);
   }
   if (m_position.PositionType()==POSITION_TYPE_SELL) {
      m_trade.PositionClose(tk);
      //Sleep(ONE_MIN);
      tk_new = OpenBuy(sym,lot,cmt);
   }
   
   return tk_new;
}
void sendPairProfit(long idx, long idy, float profit)
{
   string stx = IntegerToString(idx);
   string sty = IntegerToString(idy);
   CharArray arr;
   StringToCharArray(stx,arr.a);
   StringToCharArray(sty,arr.b);
   sendPairProfitStr(arr,profit);
}

void sendLastProfit()
{
   long tk = HistoryDealGetTicket(HistoryDealsTotal()-1);
   if (tk == lastTicket) return;
   lastTicket = tk;
   switch(HistoryDealGetInteger(HistoryDealGetTicket(HistoryDealsTotal()-1),DEAL_ENTRY))
   {
      case DEAL_ENTRY_IN:
         if (PositionSelect(HistoryDealGetString(HistoryDealGetTicket(HistoryDealsTotal()-1),DEAL_SYMBOL)) == true){
            float pft = HistoryDealGetDouble(HistoryDealGetTicket(HistoryDealsTotal()-1),DEAL_PROFIT);
            if (pft>0)
            sendPositionProfit(pft);
         }
         else {
            float pft = HistoryDealGetDouble(HistoryDealGetTicket(HistoryDealsTotal()-1),DEAL_PROFIT);
            sendPositionProfit(pft);
         }
         break;
      case DEAL_ENTRY_OUT:
         if (PositionSelect(HistoryDealGetString(HistoryDealGetTicket(HistoryDealsTotal()-1),DEAL_SYMBOL)) == true){
            float pft = HistoryDealGetDouble(HistoryDealGetTicket(HistoryDealsTotal()-1),DEAL_PROFIT);
            sendPositionProfit(pft);
         }
         else {
            float pft = HistoryDealGetDouble(HistoryDealGetTicket(HistoryDealsTotal()-1),DEAL_PROFIT);
            sendPositionProfit(pft);
         }
         break;
      default:
         Alert("Reverse position. Not supported");
         break;
   }
}
//+------------------------------------------------------------------+
//| Get Time for specified bar index                                 |
//+------------------------------------------------------------------+
datetime iTime(const int index,string symbol=NULL,ENUM_TIMEFRAMES timeframe=CURRENT_PERIOD)
{
    if(symbol==NULL)
        symbol=m_symbol_Base.Name();
    if(timeframe==0)
        timeframe=Period();
    datetime Time[1];
    datetime time=0; // D'1970.01.01 00:00:00'
    int copied=CopyTime(symbol,timeframe,index,1,Time);
    if(copied>0)
        time=Time[0];
    return(time);
}
//+------------------------------------------------------------------+
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
    

    printf("buy volume %f",check_volume_lot);
    int digits = (int)SymbolInfoInteger(symbol.Name(),SYMBOL_DIGITS);
    double price = symbol.Ask();
    double tp = NormalizeDouble(price + STOP_PERCENT*price,digits);
    double sl = NormalizeDouble(price - STOP_PERCENT*price,digits);
    

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
    double ask  = symbol.Ask();
    double pv = SymbolInfoDouble(symbol.Name(),SYMBOL_TRADE_TICK_VALUE) * SymbolInfoDouble(symbol.Name(),SYMBOL_POINT);
    double tp = NormalizeDouble(price - STOP_PERCENT*price,digits);
    double sl = NormalizeDouble(price + STOP_PERCENT*price,digits);

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
float IsProfit()
{
    double total_profit=0.0;
    int num_pos = PositionsTotal();
    if (max_pos < num_pos) max_pos = num_pos;
    PrintFormat("Total positions: %d, Max pos: %d",num_pos,max_pos);
    
    for(int i=PositionsTotal()-1; i>=0; i--) { // returns the number of current positions
        if(m_position.SelectByIndex(i))     // selects the position by index for further access to its properties
            if((m_position.Symbol()==m_symbol_Base.Name() ) && m_position.Magic()==m_magic) {
                total_profit=total_profit+m_position.Commission()+m_position.Swap()+m_position.Profit();
            }
    }
    PrintFormat("Total profit: %f",total_profit);
    
    if(total_profit>InpVirtualProfit) {
        PrintFormat("Total profit higher than %f, closing all positions...",InpVirtualProfit);
        for(int j=PositionsTotal()-1; j>=0; j--) { // returns the number of current positions
            if(m_position.SelectByIndex(j)) {// selects the position by index for further access to its properties
                if((m_position.Symbol()==m_symbol_Base.Name()) && m_position.Magic()==m_magic) {
                    datetime t_cur = TimeCurrent();
                    datetime t_pos = m_position.Time();
                    if (t_cur - t_pos < 5*60) continue; // close positions older than 10 min
                    //if (m_position.Profit() < 0.1) continue;
                    m_trade.PositionClose(m_position.Ticket()); // close a position by the specified symbol
                    PrintFormat("Position closed: %d",m_position.Ticket());
                }
            }
        }
        
    }
    return total_profit;
}

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
void closeTypeYPairs(ENUM_POSITION_TYPE y_pos_type) {
   CPositionInfo pos;
   int NP = PositionsTotal();
   long tks[];
   ArrayResize(tks,NP);
   int k=0;
   for (int i = 0; i < NP; i++) {
      if(!pos.SelectByIndex(i)) continue;
      string cmt = pos.Comment();
      if(cmt==NULL || cmt=="") continue; // it's x-position
      // it's y-position
      if(pos.PositionType() != y_pos_type) continue;
      long ty = pos.Ticket();
      long tx = getPairedTicket(ty);
      
      tks[k++] = tx;
      tks[k++] = ty;
   }
   
   for(int i=0; i < k; i++) {
      while(pos.SelectByTicket(tks[i]))
         m_trade.PositionClose(tks[i]);
   }
   
   ArrayFree(tks);
}

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
 
void updateMinMaxPairProfit() {

   for(int i=PositionsTotal()-1; i >=0; i--) {
      if(!m_position.SelectByIndex(i)) continue;
      string cmt = m_position.Comment();
      if(cmt==NULL || cmt=="") continue;

      long ty = m_position.Ticket();
      long tx = getPairedTicket(ty);
      
      double pfx=0,pfy=0;
      if(m_position.SelectByTicket(tx)) 
         pfx = m_position.Profit()+m_position.Commission()+m_position.Swap();
      if(m_position.SelectByTicket(ty)) 
         pfy = m_position.Profit()+m_position.Commission()+m_position.Swap();
         
      double profit = pfx+pfy;
      
      if (profit > g_maxPairProfit) 
         g_maxPairProfit = profit;
      if(profit < g_minPairProfit)
         g_minPairProfit = profit;
   }
}