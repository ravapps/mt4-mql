/**
 * Yen Trader
 *
 * @see  https://www.forexfactory.com/showthread.php?t=595898
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////// Configuration ////////////////////////////////////////////////////////

extern string Signal.Timeframe       = "M1 | M5 | M15 | M30 | H1 | H4 | D1";

extern string _____________________________1_ = "";                  // Symbol Setup
extern string Major_Code             = "GBPUSD";                     // Major Pair Code
extern string UJ_Code                = "USDJPY";                     // DollarYen Pair Code
extern string JPY_Cross              = "GBPJPY";                     // Yen Cross Pair Code
extern string major_pos              = "L";                          // Major Direction Left/Right

extern string _____________________________2_ = "";                  // Trade Setup
extern double Fixed_Lot_Size         = 0;                            // Fixed Lots (0 = variable lots)
extern double Bal_Perc_Lot_Size      = 1;                            // Variable Lots as % of Balance
extern double TakeProfit.Pips        = 500;                          // 0 = disabled
extern double StopLoss.Pips          = 100;                          // 0 = disabled
extern double Breakeven.Pips         = 20;                           // 0 = disabled
extern int    TrailingStop.Pips      = 20;                           // 0 = disabled
extern int    TrailingStop.Step.Pips = 1;                            // update step size
extern int    max_orders             = 10;                           // Max Open Trades
extern string Averaging.Type         = "Pyramid | Average | Both*";  // averaging type for splitting positions
extern bool   close_on_opposite      = false;                        // close open positions on opposite signal
extern bool   hedge_trades           = true;                         // hedge open positions on opposite signal

extern string _____________________________3_ = "";                  // Entry Signal Setup
extern int    lookback_bars          = 2;                            // Lookback bars (0 to disable)
extern string Lookback.PriceType     = "Close | High/Low*";          // Price Type of Lookback bars
extern bool   RSI                    = false;                        // Relative Strength Index
extern bool   RVI                    = false;                        // Relative Vigor Index
extern bool   CCI                    = false;                        // Commodity Channel Index
extern int    MA_Period              = 34;                           // Moving Average Period (0 to disable)
extern string MA.Method              = "SMA | EMA | SMMA* | LWMA";

extern string _____________________________4_ = "";                  // Order Management
extern int    max_spread             = 100;                          // Max Spread
extern int    max_slippage           = 10;                           // Max Slippage
extern int    Magic_Number           = 160704;                       // Magic Number

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/expert.mqh>
#include <stdfunctions.mqh>
#include <stdlibs.mqh>

int      time_frame;                         // signal timeframe
int      entry_type;                         // averaging type
int      price_type;                         // price type of lookback bars
int      MA_Method;                          // moving average method

datetime bar_time;
double   ind1, ind2, sig1, sig2;
int      order_max_tries = 3;

#define ENTRY_PYRAMID   1                    // pyramiding
#define ENTRY_AVERAGE   2                    // averaging
#define ENTRY_BOTH      3                    // both

#define TPRICE_CLOSE    1                    // close price
#define TPRICE_HIGHLOW  2                    // high/low price


/**
 * Initialization
 *
 * @return int - error status
 */
int onInit() {
   // Signal.Timeframe
   time_frame = StrToPeriod(Signal.Timeframe, F_ERR_INVALID_PARAMETER);
   if (time_frame==-1 || time_frame > PERIOD_D1) return(catch("onInit(1)  Invalid input parameter Signal.Timeframe = "+ DoubleQuoteStr(Signal.Timeframe), ERR_INVALID_INPUT_PARAMETER));
   Signal.Timeframe = PeriodDescription(time_frame);

   // Averaging.Type
   string elems[], sValue = StringToLower(Averaging.Type);
   if (Explode(sValue, "*", elems, 2) > 1) {
      int size = Explode(elems[0], "|", elems, NULL);
      sValue = elems[size-1];
   }
   sValue = StringTrim(sValue);
   if      (StringStartsWith("pyramid", sValue)) { entry_type = ENTRY_PYRAMID; Averaging.Type = "Pyramid"; }
   else if (StringStartsWith("average", sValue)) { entry_type = ENTRY_AVERAGE; Averaging.Type = "Average"; }
   else if (StringStartsWith("both",    sValue)) { entry_type = ENTRY_BOTH;    Averaging.Type = "Both";    }
   else                                          return(catch("onInit(2)  Invalid input parameter Averaging.Type = "+ DoubleQuoteStr(Averaging.Type), ERR_INVALID_INPUT_PARAMETER));

   // Lookback.PriceType
   sValue = StringToLower(Lookback.PriceType);
   if (Explode(sValue, "*", elems, 2) > 1) {
      size = Explode(elems[0], "|", elems, NULL);
      sValue = elems[size-1];
   }
   sValue = StringTrim(sValue);
   if      (StringStartsWith("close",    sValue)) { price_type = TPRICE_CLOSE;   Lookback.PriceType = "Close"; }
   else if (StringStartsWith("highlow",  sValue)) { price_type = TPRICE_HIGHLOW; Lookback.PriceType = "High/Low"; }
   else if (StringStartsWith("high-low", sValue)) { price_type = TPRICE_HIGHLOW; Lookback.PriceType = "High/Low"; }
   else if (StringStartsWith("high/low", sValue)) { price_type = TPRICE_HIGHLOW; Lookback.PriceType = "High/Low"; }
   else                                          return(catch("onInit(3)  Invalid input parameter Lookback.PriceType = "+ DoubleQuoteStr(Lookback.PriceType), ERR_INVALID_INPUT_PARAMETER));

   // MA.Method
   if (Explode(MA.Method, "*", elems, 2) > 1) {
      size = Explode(elems[0], "|", elems, NULL);
      sValue = elems[size-1];
   }
   else sValue = StringTrim(MA.Method);
   MA_Method = StrToMaMethod(sValue, F_ERR_INVALID_PARAMETER);
   if (MA_Method == -1 || MA_Method > MODE_LWMA) return(catch("onInit(4)  Invalid input parameter MA.Method = "+ DoubleQuoteStr(MA.Method), ERR_INVALID_INPUT_PARAMETER));
   MA.Method = MaMethodDescription(MA_Method);




   // legacy code
   if (invalid_pair(Major_Code))                                    return(catch("onInit(5)  First pair code ("+ Major_Code +") is invalid", ERR_INVALID_INPUT_PARAMETER));
   if (invalid_pair(UJ_Code))                                       return(catch("onInit(6)  Second pair code ("+ UJ_Code +") is invalid", ERR_INVALID_INPUT_PARAMETER));
   if (invalid_pair(JPY_Cross))                                     return(catch("onInit(7)  Second pair code ("+ JPY_Cross +") is invalid", ERR_INVALID_INPUT_PARAMETER));
   if (time_frame < Period())                                       return(catch("onInit(8)  Invalid input signal timeframe ("+ time_frame +") is less than trading timeframe ("+ Period() +")", ERR_INVALID_INPUT_PARAMETER));
   if (TrailingStop.Pips > 0 && Breakeven.Pips > TrailingStop.Pips) return(catch("onInit(9)  Breakeven pips ("+ Breakeven.Pips +") is greater than trailing stop ("+ TrailingStop.Pips +")", ERR_INVALID_INPUT_PARAMETER));
   if (!lookback_bars && !MA_Period && !RSI && !RVI && !CCI)        return(catch("onInit(10)  Error: No signal triggers/indicators selected.", ERR_INVALID_INPUT_PARAMETER));

   return(catch("onInit(11)"));
}


/**
 * Main function
 *
 * @return int - error status
 */
int onTick() {
   if (Breakeven.Pips    > 0) move_to_BE();
   if (TrailingStop.Pips > 0) trail_stop();

   if (Time[0] > bar_time) {
      if (total_orders() < max_orders) {
         bool buy, sell;

         if (lookback_bars > 1) {
            if (price_type == TPRICE_HIGHLOW) {
               buy = (major_pos == "L"
                   && iClose(Major_Code, time_frame, 1) > iHigh(Major_Code, time_frame, iHighest(Major_Code, time_frame, MODE_HIGH, lookback_bars, 2))
                   && iClose(UJ_Code,    time_frame, 1) > iHigh(UJ_Code,    time_frame, iHighest(UJ_Code,    time_frame, MODE_HIGH, lookback_bars, 2)))
                   ||
                   (major_pos == "R"
                   && iClose(Major_Code, time_frame, 1) <  iLow(Major_Code, time_frame,  iLowest(Major_Code, time_frame, MODE_LOW,  lookback_bars, 2))
                   && iClose(UJ_Code,    time_frame, 1) > iHigh(UJ_Code,    time_frame, iHighest(UJ_Code,    time_frame, MODE_HIGH, lookback_bars, 2)));

               sell = (major_pos == "L"
                    && iClose(Major_Code, time_frame, 1) < iLow(Major_Code, time_frame, iLowest(Major_Code, time_frame, MODE_LOW, lookback_bars, 2))
                    && iClose(UJ_Code,    time_frame, 1) < iLow(UJ_Code,    time_frame, iLowest(UJ_Code,    time_frame, MODE_LOW, lookback_bars, 2)))
                    ||
                    (major_pos == "R"
                    && iClose(Major_Code, time_frame, 1) > iHigh(Major_Code, time_frame, iHighest(Major_Code, time_frame, MODE_HIGH, lookback_bars, 2))
                    && iClose(UJ_Code,    time_frame, 1) <  iLow(UJ_Code,    time_frame,  iLowest(UJ_Code,    time_frame, MODE_LOW,  lookback_bars, 2)));
            }
            else {
               buy = (major_pos == "L"
                      && iClose(Major_Code, time_frame, 1) > iClose(Major_Code, time_frame, lookback_bars)
                      && iClose(UJ_Code,    time_frame, 1) > iClose(UJ_Code,    time_frame, lookback_bars))
                     ||
                     (major_pos == "R"
                      && iClose(Major_Code, time_frame, 1) < iClose(Major_Code, time_frame, lookback_bars)
                      && iClose(UJ_Code,    time_frame, 1) > iClose(UJ_Code,    time_frame, lookback_bars));

               sell = (major_pos == "L"
                       && iClose(Major_Code, time_frame, 1) < iClose(Major_Code, time_frame, lookback_bars)
                       && iClose(UJ_Code,    time_frame, 1) < iClose(UJ_Code,    time_frame, lookback_bars))
                      ||
                      (major_pos == "R"
                       && iClose(Major_Code, time_frame, 1) > iClose(Major_Code, time_frame, lookback_bars)
                       && iClose(UJ_Code,    time_frame, 1) < iClose(UJ_Code,    time_frame, lookback_bars));
            }
         }
         else {
            buy  = true;
            sell = true;
         }

         buy  = buy  && (entry_type==ENTRY_BOTH
                     || (entry_type==ENTRY_AVERAGE && Close[1] < Open[1])
                     || (entry_type==ENTRY_PYRAMID && Close[1] > Open[1]));

         sell = sell && (entry_type==ENTRY_BOTH
                     || (entry_type==ENTRY_AVERAGE && Close[1] > Open[1])
                     || (entry_type==ENTRY_PYRAMID && Close[1] < Open[1]));

         if (RSI) {
            ind1 = iRSI(Major_Code, time_frame, 14, PRICE_CLOSE, 1);
            ind2 = iRSI(UJ_Code,    time_frame, 14, PRICE_CLOSE, 1);
            buy  = buy  && ind2 > 50 && ((major_pos=="L" && ind1 > 50)
                                      || (major_pos=="R" && ind1 < 50));
            sell = sell && ind2 < 50 && ((major_pos=="L" && ind1 < 50)
                                      || (major_pos=="R" && ind1 > 50));
         }

         if (CCI) {
            ind1 = iCCI(Major_Code, time_frame, 14, PRICE_TYPICAL, 1);
            ind2 = iCCI(UJ_Code,    time_frame, 14, PRICE_TYPICAL, 1);
            buy  = buy  && ind2 > 0 && ((major_pos=="L" && ind1 > 0)
                                     || (major_pos=="R" && ind1 < 0));
            sell = sell && ind2 < 0 && ((major_pos=="L" && ind1 < 0)
                                     || (major_pos=="R" && ind1 > 0));
         }

         if (RVI) {
            ind1 = iRVI(Major_Code, time_frame, 10, MODE_MAIN,   1);
            sig1 = iRVI(Major_Code, time_frame, 10, MODE_SIGNAL, 1);
            ind2 = iRVI(UJ_Code,    time_frame, 10, MODE_MAIN,   1);
            sig2 = iRVI(UJ_Code,    time_frame, 10, MODE_SIGNAL, 1);
            buy  = buy  && ind2 > sig2 && ((major_pos=="L" && ind1 > sig1)
                                        || (major_pos=="R" && ind1 < sig1));
            sell = sell && ind2 < sig2 && ((major_pos=="L" && ind1 < sig1)
                                        || (major_pos=="R" && ind1 > sig1));
         }

         if (MA_Period > 0) {
            ind1 = iMA(Major_Code, time_frame, MA_Period, 0, MA_Method, PRICE_CLOSE, 1);
            ind2 = iMA(UJ_Code,    time_frame, MA_Period, 0, MA_Method, PRICE_CLOSE, 1);
            buy  = buy  && iClose(UJ_Code, time_frame, 1) > ind2 && ((major_pos=="L" && iClose(Major_Code, time_frame, 1) > ind1)
                                                                  || (major_pos=="R" && iClose(Major_Code, time_frame, 1) < ind1));
            sell = sell && iClose(UJ_Code, time_frame, 1) < ind2 && ((major_pos=="L" && iClose(Major_Code, time_frame, 1) < ind1)
                                                                  || (major_pos=="R" && iClose(Major_Code, time_frame, 1) > ind1));
         }

         if (buy) {
            if (close_on_opposite)                     close_current_orders(OP_SELL);
            if (hedge_trades || !exist_order(OP_SELL)) market_buy_order();
         }
         if (sell) {
            if (close_on_opposite)                    close_current_orders(OP_BUY);
            if (hedge_trades || !exist_order(OP_BUY)) market_sell_order();
         }
      }
      bar_time = Time[0];
   }

   return(catch("onTick(1)"));
}


/**
 * Count the number of open positions of the strategy.
 *
 * @return int - number of open positions or EMPTY (-1) in case of errors
 */
int total_orders() {
   int positions, orders = OrdersTotal();

   for (int i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         break;
      if (OrderMagicNumber()==Magic_Number && OrderSymbol()==Symbol() && OrderType()<=OP_SELL)
         positions++;
   }

   if (!catch("total_orders(1)"))
      return(positions);
   return(EMPTY);
}


/**
 * Submit a Buy Market order.
 */
void market_buy_order() {
   double lots, takeprofit, stoploss;

   if (Fixed_Lot_Size > 0) lots = Fixed_Lot_Size;
   else                    lots = NormalizeLots(AccountBalance() * Bal_Perc_Lot_Size/100 / MarketInfo(Symbol(), MODE_MARGINREQUIRED));

   if (TakeProfit.Pips > 0) takeprofit = Ask + TakeProfit.Pips*Pip;
   if (StopLoss.Pips   > 0) stoploss   = Ask - StopLoss.Pips*Pip;

   int tries = 0;
   while (tries < order_max_tries && MarketInfo(Symbol(), MODE_ASK)-MarketInfo(Symbol(), MODE_BID) <= max_spread*Point) {
      if (OrderSend(Symbol(), OP_BUY, lots, MarketInfo(Symbol(), MODE_ASK), max_slippage, stoploss, takeprofit, "YT", Magic_Number, 0, Blue) > 0)
         break;
      warn("market_buy_order(1)  Error in Sending a Buy Order", GetLastError());
      tries++;
   }
   catch("market_buy_order(2)");
}


/**
 * Submit a Sell Market order.
 */
void market_sell_order() {
   double lots, takeprofit, stoploss;

   if (Fixed_Lot_Size > 0) lots = Fixed_Lot_Size;
   else                    lots = NormalizeLots(AccountBalance() * Bal_Perc_Lot_Size/100 / MarketInfo(Symbol(), MODE_MARGINREQUIRED));

   if (TakeProfit.Pips > 0) takeprofit = Bid - TakeProfit.Pips*Pip;
   if (StopLoss.Pips   > 0) stoploss   = Bid + StopLoss.Pips*Pip;

   int tries = 0;
   while (tries < order_max_tries && MarketInfo(Symbol(), MODE_ASK)-MarketInfo(Symbol(), MODE_BID) <= max_spread*Point) {
      if (OrderSend(Symbol(), OP_SELL, lots, MarketInfo(Symbol(), MODE_BID), max_slippage, stoploss, takeprofit, "YT", Magic_Number, 0, Red) > 0)
         break;
      warn("market_sell_order(1)  Error in Sending a Sell Order", GetLastError());
      tries++;
   }
   catch("market_sell_order(2)");
}


/**
 * Whether or not an open ticket of the specified order type exists.
 *
 * @return bool
 */
bool exist_order(int ord_type) {
   int  orders = OrdersTotal();
   bool result = false;

   for (int i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         break;
      if (OrderMagicNumber()==Magic_Number && OrderSymbol()==Symbol() && OrderType()==ord_type) {
         result = true;
         break;
      }
   }

   if (!catch("exist_order(1)"))
      return(result);
   return(false);
}


/**
 * Close all open positions of the specified type.
 */
void close_current_orders(int ord_type) {
   for (int i=OrdersTotal()-1; i >= 0; i--) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         break;

      if (OrderSymbol()==Symbol() && OrderMagicNumber()==Magic_Number && OrderType()==ord_type) {
         int tries = 0;
         while (tries < order_max_tries) {
            double price = MarketInfo(Symbol(), ifInt(OrderType()==OP_BUY, MODE_BID, MODE_ASK));
            if (OrderClose(OrderTicket(), OrderLots(), price, 100, NULL))
               break;
            warn("close_current_orders(1)  OrderClose() error", GetLastError());
         }
      }
   }
   catch("close_current_orders(2)");
}


/**
 * Trail stops of matching open positions.
 */
void trail_stop() {
   if (!TrailingStop.Pips)
      return;

   double stop;
   int tries, orders = OrdersTotal();

   for (int i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         break;

      if (OrderMagicNumber()==Magic_Number && OrderSymbol()==Symbol()) {
         RefreshRates();
         stop  = 0;
         tries = 0;

         if (OrderType() == OP_BUY) {
            if (Bid > OrderOpenPrice() + TrailingStop.Pips*Pip) {
               if      (OrderStopLoss() < OrderOpenPrice())                                       stop = Bid - TrailingStop.Pips*Pip;
               else if (Bid > OrderStopLoss() + (TrailingStop.Pips + TrailingStop.Step.Pips)*Pip) stop = Bid - TrailingStop.Pips*Pip;
            }
            while (stop && tries < order_max_tries) {
               if (OrderModify(OrderTicket(), OrderOpenPrice(), stop, OrderTakeProfit(), 0, Red))
                  break;
               warn("trail_stop(1)  Order SL Modify Error", GetLastError());
               tries++;
            }
         }
         else if (OrderType() == OP_SELL) {
            if (Ask < OrderOpenPrice() - TrailingStop.Pips*Pip) {
               if      (!OrderStopLoss() || OrderStopLoss() > OrderOpenPrice())                   stop = Ask + TrailingStop.Pips*Pip;
               else if (Ask < OrderStopLoss() - (TrailingStop.Pips + TrailingStop.Step.Pips)*Pip) stop = Ask + TrailingStop.Pips*Pip;
            }
            while (stop && tries < order_max_tries) {
               if (OrderModify(OrderTicket(), OrderOpenPrice(), stop, OrderTakeProfit(), 0, Red))
                  break;
               warn("trail_stop(2)  Order SL Modify Error", GetLastError());
               tries++;
            }
         }
      }
   }
   catch("trail_stop(3)");
}


/**
 * Move stops of matching open positions to Breakeven.
 */
void move_to_BE() {
   if (!Breakeven.Pips)
      return;

   double stop;
   int tries, orders = OrdersTotal();

   for (int i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         break;

      if (OrderMagicNumber()==Magic_Number && OrderSymbol()==Symbol()) {
         RefreshRates();
         stop  = 0;
         tries = 0;

         if (OrderType() == OP_BUY) {
            if (Bid - OrderOpenPrice() > Breakeven.Pips*Pip && (!OrderStopLoss() || OrderOpenPrice() > OrderStopLoss())) {
               stop = OrderOpenPrice() + Breakeven.Pips*Pip;
               while (tries < order_max_tries && stop > OrderStopLoss()) {
                  if (OrderModify(OrderTicket(), OrderOpenPrice(), stop, OrderTakeProfit(), 0, Red))
                     break;
                  warn("move_to_BE(1)  Order move to BE Modify error", GetLastError());
                  tries++;
               }
            }
         }
         else if (OrderType() == OP_SELL) {
            if (OrderOpenPrice() - Ask > Breakeven.Pips*Pip && (!OrderStopLoss() || OrderOpenPrice() < OrderStopLoss())) {
               stop = OrderOpenPrice() - Breakeven.Pips*Pip;
               while (tries < order_max_tries && stop < OrderStopLoss()) {
                  if (OrderModify(OrderTicket(), OrderOpenPrice(), stop, OrderTakeProfit(), 0, Red))
                     break;
                  warn("move_to_BE(2)  Order move to BE Modify error", GetLastError());
                  tries++;
               }
            }
         }
      }
   }
   catch("move_to_BE(3)");
}


/**
 * Whether or not a symbol is subscribed. A symbol is subscribed if it's visible in the MarketWatch window.
 *
 * @param  string symbol
 *
 * @return bool
 */
bool invalid_pair(string symbol) {
   return(!MarketInfo(symbol, MODE_TIME) || GetLastError());
}

