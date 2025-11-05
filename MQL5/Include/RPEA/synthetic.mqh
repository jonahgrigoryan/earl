#ifndef RPEA_SYNTHETIC_MQH
#define RPEA_SYNTHETIC_MQH
// synthetic.mqh - Synthetic XAUEUR price & bar manager (Task 11)
// References: finalspec.md (Synthetic Cross Support), .kiro/specs/rpea-m3/design.md §Synthetic Manager Interface

//---------------------------------------------------------------------------
// Constants & helpers
//---------------------------------------------------------------------------

#define SYNTH_SYMBOL_XAUEUR   "XAUEUR"
#define SYNTH_LEG_XAUUSD      "XAUUSD"
#define SYNTH_LEG_EURUSD      "EURUSD"

// Forward declarations for default providers
bool  Synthetic_DefaultTickProvider(const string symbol, MqlTick &out_tick);
int   Synthetic_DefaultRatesProvider(const string symbol,
                                     const ENUM_TIMEFRAMES timeframe,
                                     const int start_pos,
                                     const int count,
                                     MqlRates &rates[]);

//---------------------------------------------------------------------------
// Data structures
//---------------------------------------------------------------------------

struct SyntheticBar
{
   datetime time;
   double   open;
   double   high;
   double   low;
   double   close;
   long     tick_volume;
};

struct SyntheticCacheEntry
{
   string          symbol;
   ENUM_TIMEFRAMES timeframe;
   SyntheticBar    bars[];
   datetime        last_bar_time;
   datetime        last_build_time;
   int             forward_filled_bars;
   bool            valid;
};

typedef bool (*SyntheticTickProvider)(const string symbol, MqlTick &out_tick);
typedef int  (*SyntheticRatesProvider)(const string symbol,
                                       const ENUM_TIMEFRAMES timeframe,
                                       const int start_pos,
                                       const int count,
                                       MqlRates &rates[]);

//---------------------------------------------------------------------------
// Utility functions
//---------------------------------------------------------------------------

datetime Synthetic_GetLastTickTime(const string symbol)
{
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return 0;
   return (datetime)tick.time;
}

//---------------------------------------------------------------------------
// Synthetic Manager
//---------------------------------------------------------------------------

class SyntheticManager
{
private:
   SyntheticTickProvider m_tick_provider;
   SyntheticRatesProvider m_rates_provider;
   SyntheticCacheEntry    m_cache[];
   string                 m_unsupported_logged[];
   int                    m_cache_limit;
   bool                   m_forward_fill_enabled;
   int                    m_max_gap_bars;
   int                    m_quote_max_age_ms;

   void     UpdateConfigSnapshot();
   bool     EnsureSymbolSelected(const string symbol) const;
   int      FindCacheIndex(const string symbol, const ENUM_TIMEFRAMES timeframe) const;
   void     EnsureCacheCapacity();
   void     RemoveCacheEntry(const int index);
   double   ExtractAppliedPrice(const MqlTick &tick, const ENUM_APPLIED_PRICE price_type) const;
   bool     AreTicksStale(const MqlTick &tick_a, const MqlTick &tick_b) const;
   bool     AlignRatesToBars(const MqlRates &xau_rates[], const int xau_size,
                             const MqlRates &eur_rates[], const int eur_size,
                             const ENUM_TIMEFRAMES tf, const int count,
                             SyntheticBar &out_bars[], int &forward_filled) const;
   bool     AppendTimeline(datetime &timeline[], const datetime value) const;
   bool     ShouldForwardFill(const bool has_previous, const int gap_depth) const;
   bool     WasUnsupportedLogged(const string symbol) const;
   void     MarkUnsupportedLogged(const string symbol);

public:
   SyntheticManager();

   double GetSyntheticPrice(const string synthetic_symbol, const ENUM_APPLIED_PRICE price_type);
   double CalculateXAUEURPrice(const ENUM_APPLIED_PRICE price_type);

   bool   AreQuotesStale(const string symbol_a, const string symbol_b);

   bool   BuildSyntheticBars(const string synthetic_symbol, const ENUM_TIMEFRAMES tf, const int count);
   bool   GetCachedBars(const string synthetic_symbol, const ENUM_TIMEFRAMES tf, SyntheticBar &out[], const int count);
   void   InvalidateCache(const string synthetic_symbol);
   void   InvalidateCache(const string synthetic_symbol, const ENUM_TIMEFRAMES tf);
   void   Clear();

   double ScaleSyntheticDistance(const double xaueur_distance, const double eurusd_rate) const;

   // Test hooks
   void   SetTickProvider(SyntheticTickProvider provider);
   void   SetRatesProvider(SyntheticRatesProvider provider);
   void   ResetProviders();
   int    CacheEntries() const { return ArraySize(m_cache); }
};

SyntheticManager g_synthetic_manager;

//---------------------------------------------------------------------------
// SyntheticManager implementation
//---------------------------------------------------------------------------

SyntheticManager::SyntheticManager()
{
   m_tick_provider = Synthetic_DefaultTickProvider;
   m_rates_provider = Synthetic_DefaultRatesProvider;
   ArrayResize(m_cache, 0);
   ArrayResize(m_unsupported_logged, 0);
   m_cache_limit = DEFAULT_SyntheticBarCacheSize;
   m_forward_fill_enabled = DEFAULT_ForwardFillGaps;
   m_max_gap_bars = DEFAULT_MaxGapBars;
   m_quote_max_age_ms = DEFAULT_QuoteMaxAgeMs;
}

void SyntheticManager::UpdateConfigSnapshot()
{
   int limit = SyntheticBarCacheSize;
   if(limit <= 0)
      limit = DEFAULT_SyntheticBarCacheSize;
   m_cache_limit = limit;

   m_forward_fill_enabled = ForwardFillGaps;

   m_max_gap_bars = MaxGapBars;
   if(m_max_gap_bars < 0)
      m_max_gap_bars = 0;

   m_quote_max_age_ms = QuoteMaxAgeMs;
   if(m_quote_max_age_ms <= 0)
      m_quote_max_age_ms = DEFAULT_QuoteMaxAgeMs;
}

bool SyntheticManager::EnsureSymbolSelected(const string symbol) const
{
   if(SymbolInfoInteger(symbol, SYMBOL_SELECT))
      return true;
   return SymbolSelect(symbol, true);
}

int SyntheticManager::FindCacheIndex(const string symbol, const ENUM_TIMEFRAMES timeframe) const
{
   int size = ArraySize(m_cache);
   for(int i=0;i<size;i++)
   {
      if(m_cache[i].symbol == symbol && m_cache[i].timeframe == timeframe)
         return i;
   }
   return -1;
}

void SyntheticManager::RemoveCacheEntry(const int index)
{
   if(index < 0 || index >= ArraySize(m_cache))
      return;
   ArrayRemove(m_cache, index);
}

void SyntheticManager::EnsureCacheCapacity()
{
   int size = ArraySize(m_cache);
   if(size <= m_cache_limit)
      return;

   int oldest_index = -1;
   datetime oldest_build = 0;
   bool oldest_set = false;

   for(int i=0;i<size;i++)
   {
      if(!oldest_set || m_cache[i].last_build_time < oldest_build)
      {
         oldest_build = m_cache[i].last_build_time;
         oldest_index = i;
         oldest_set = true;
      }
   }

   if(oldest_index >= 0)
      RemoveCacheEntry(oldest_index);
}

double SyntheticManager::ExtractAppliedPrice(const MqlTick &tick, const ENUM_APPLIED_PRICE price_type) const
{
   double bid = tick.bid;
   double ask = tick.ask;
   double last = tick.last;
   if(last <= 0.0)
      last = (bid + ask) * 0.5;

   switch(price_type)
   {
#ifdef PRICE_BID
      case PRICE_BID:
         return bid;
#endif
#ifdef PRICE_ASK
      case PRICE_ASK:
         return ask;
#endif
      case PRICE_MEDIAN:
         return (bid + ask) * 0.5;
      case PRICE_TYPICAL:
         return (bid + ask + last) / 3.0;
      case PRICE_WEIGHTED:
         return (bid + ask + last + last) / 4.0;
      case PRICE_OPEN:
      case PRICE_HIGH:
      case PRICE_LOW:
      case PRICE_CLOSE:
      default:
         return last;
   }
}

bool SyntheticManager::AreTicksStale(const MqlTick &tick_a, const MqlTick &tick_b) const
{
   datetime now = TimeCurrent();
   double age_a_ms = (double)(now - (datetime)tick_a.time) * 1000.0;
   double age_b_ms = (double)(now - (datetime)tick_b.time) * 1000.0;

   if(age_a_ms > m_quote_max_age_ms || age_b_ms > m_quote_max_age_ms)
   {
      PrintFormat("[Synthetic] Quotes stale ageA=%.0fms ageB=%.0fms limit=%d", age_a_ms, age_b_ms, m_quote_max_age_ms);
      return true;
   }
   return false;
}

bool SyntheticManager::AppendTimeline(datetime &timeline[], const datetime value) const
{
   int size = ArraySize(timeline);
   if(size > 0 && timeline[size - 1] == value)
      return false;
   ArrayResize(timeline, size + 1);
   timeline[size] = value;
   return true;
}

bool SyntheticManager::ShouldForwardFill(const bool has_previous, const int gap_depth) const
{
   if(!m_forward_fill_enabled || !has_previous)
      return false;
   return (gap_depth + 1) <= m_max_gap_bars;
}

bool SyntheticManager::AlignRatesToBars(const MqlRates &xau_rates[], const int xau_size,
                                        const MqlRates &eur_rates[], const int eur_size,
                                        const ENUM_TIMEFRAMES tf, const int count,
                                        SyntheticBar &out_bars[], int &forward_filled) const
{
   if(count <= 0)
      return false;

   int xau_start = xau_size - (count + m_max_gap_bars);
   if(xau_start < 0)
      xau_start = 0;

   int eur_start = eur_size - (count + m_max_gap_bars);
   if(eur_start < 0)
      eur_start = 0;

   datetime timeline[];
   int x_index = xau_start;
   int e_index = eur_start;

   while(x_index < xau_size && e_index < eur_size)
   {
      datetime tx = xau_rates[x_index].time;
      datetime te = eur_rates[e_index].time;
      if(tx == te)
      {
         AppendTimeline(timeline, tx);
         x_index++;
         e_index++;
         continue;
      }
      if(tx < te)
      {
         AppendTimeline(timeline, tx);
         x_index++;
         continue;
      }
      AppendTimeline(timeline, te);
      e_index++;
   }

   while(x_index < xau_size)
   {
      AppendTimeline(timeline, xau_rates[x_index].time);
      x_index++;
   }

   while(e_index < eur_size)
   {
      AppendTimeline(timeline, eur_rates[e_index].time);
      e_index++;
   }

   int timeline_size = ArraySize(timeline);
   if(timeline_size == 0)
      return false;

   MqlRates x_last;
   MqlRates e_last;
   bool x_has_last = false;
   bool e_has_last = false;
   int x_gap = 0;
   int e_gap = 0;
   forward_filled = 0;

   ArrayResize(out_bars, 0);

   int x_ptr = xau_start;
   int e_ptr = eur_start;

   for(int i=0;i<timeline_size;i++)
   {
      datetime stamp = timeline[i];

      bool x_actual = false;
      while(x_ptr < xau_size && xau_rates[x_ptr].time < stamp)
         x_ptr++;
      if(x_ptr < xau_size && xau_rates[x_ptr].time == stamp)
      {
         x_last = xau_rates[x_ptr];
         x_has_last = true;
         x_ptr++;
         x_gap = 0;
         x_actual = true;
      }
      else
      {
         if(!ShouldForwardFill(x_has_last, x_gap))
         {
            if(m_forward_fill_enabled && x_has_last && (x_gap + 1) > m_max_gap_bars)
            {
               PrintFormat("[Synthetic] Gap exceeded (bars=%d) leg=%s", x_gap + 1, SYNTH_LEG_XAUUSD);
               return false;
            }
            continue;
         }
         x_gap++;
         forward_filled++;
      }

      bool e_actual = false;
      while(e_ptr < eur_size && eur_rates[e_ptr].time < stamp)
         e_ptr++;
      if(e_ptr < eur_size && eur_rates[e_ptr].time == stamp)
      {
         e_last = eur_rates[e_ptr];
         e_has_last = true;
         e_ptr++;
         e_gap = 0;
         e_actual = true;
      }
      else
      {
         if(!ShouldForwardFill(e_has_last, e_gap))
         {
            if(m_forward_fill_enabled && e_has_last && (e_gap + 1) > m_max_gap_bars)
            {
               PrintFormat("[Synthetic] Gap exceeded (bars=%d) leg=%s", e_gap + 1, SYNTH_LEG_EURUSD);
               return false;
            }
            continue;
         }
         e_gap++;
         forward_filled++;
      }

      if(!x_has_last || !e_has_last)
         continue;

      SyntheticBar bar;
      bar.time = stamp;

      if(e_last.open == 0.0 || e_last.high == 0.0 || e_last.low == 0.0 || e_last.close == 0.0)
      {
         PrintFormat("[Synthetic] Zero denominator while building XAUEUR bars at %s", TimeToString(stamp, TIME_DATE|TIME_MINUTES));
         return false;
      }

      bar.open = x_last.open / e_last.open;
      bar.high = x_last.high / e_last.high;
      bar.low  = x_last.low  / e_last.low;
      bar.close= x_last.close/ e_last.close;
      bar.tick_volume = (x_actual && e_actual) ? (long)MathMin((double)x_last.tick_volume, (double)e_last.tick_volume) : 0;

      int current_size = ArraySize(out_bars);
      ArrayResize(out_bars, current_size + 1);
      out_bars[current_size] = bar;
   }

   int available = ArraySize(out_bars);
   if(available < count)
   {
      PrintFormat("[Synthetic] Insufficient bars for %s requested=%d available=%d", SYNTH_SYMBOL_XAUEUR, count, available);
      return false;
   }

   int trim = available - count;
   if(trim > 0)
      ArrayRemove(out_bars, 0, trim);

   return true;
}

bool SyntheticManager::WasUnsupportedLogged(const string symbol) const
{
   int size = ArraySize(m_unsupported_logged);
   for(int i=0;i<size;i++)
   {
      if(m_unsupported_logged[i] == symbol)
         return true;
   }
   return false;
}

void SyntheticManager::MarkUnsupportedLogged(const string symbol)
{
   int size = ArraySize(m_unsupported_logged);
   ArrayResize(m_unsupported_logged, size + 1);
   m_unsupported_logged[size] = symbol;
}

double SyntheticManager::GetSyntheticPrice(const string synthetic_symbol, const ENUM_APPLIED_PRICE price_type)
{
   if(synthetic_symbol == SYNTH_SYMBOL_XAUEUR)
      return CalculateXAUEURPrice(price_type);

   if(!WasUnsupportedLogged(synthetic_symbol))
   {
      PrintFormat("[Synthetic] Unsupported synthetic symbol: %s", synthetic_symbol);
      MarkUnsupportedLogged(synthetic_symbol);
   }
   return 0.0;
}

double SyntheticManager::CalculateXAUEURPrice(const ENUM_APPLIED_PRICE price_type)
{
   UpdateConfigSnapshot();

   if(!EnsureSymbolSelected(SYNTH_LEG_XAUUSD) || !EnsureSymbolSelected(SYNTH_LEG_EURUSD))
   {
      Print("[Synthetic] Failed to select XAUEUR legs");
      return 0.0;
   }

   MqlTick xau_tick;
   MqlTick eur_tick;

   if(!m_tick_provider(SYNTH_LEG_XAUUSD, xau_tick))
   {
      Print("[Synthetic] Failed to fetch XAUUSD tick");
      return 0.0;
   }

   if(!m_tick_provider(SYNTH_LEG_EURUSD, eur_tick))
   {
      Print("[Synthetic] Failed to fetch EURUSD tick");
      return 0.0;
   }

   if(AreTicksStale(xau_tick, eur_tick))
      return 0.0;

   double price_xau = ExtractAppliedPrice(xau_tick, price_type);
   double price_eur = ExtractAppliedPrice(eur_tick, price_type);

   if(price_eur == 0.0)
   {
      Print("[Synthetic] EURUSD denominator is zero");
      return 0.0;
   }

   double ratio = price_xau / price_eur;
   PrintFormat("[Synthetic] XAUEUR price type=%d xau=%.5f eur=%.5f ratio=%.5f", price_type, price_xau, price_eur, ratio);
   return ratio;
}

bool SyntheticManager::AreQuotesStale(const string symbol_a, const string symbol_b)
{
   UpdateConfigSnapshot();

   MqlTick tick_a;
   MqlTick tick_b;

   if(!m_tick_provider(symbol_a, tick_a))
      return true;

   if(!m_tick_provider(symbol_b, tick_b))
      return true;

   return AreTicksStale(tick_a, tick_b);
}

bool SyntheticManager::BuildSyntheticBars(const string synthetic_symbol, const ENUM_TIMEFRAMES tf, const int count)
{
   UpdateConfigSnapshot();

   if(synthetic_symbol != SYNTH_SYMBOL_XAUEUR)
   {
      PrintFormat("[Synthetic] BuildSyntheticBars unsupported symbol=%s", synthetic_symbol);
      return false;
   }

   if(tf != PERIOD_M1 && tf != PERIOD_H1 && tf != PERIOD_D1)
   {
      PrintFormat("[Synthetic] Unsupported timeframe for %s tf=%s", synthetic_symbol, EnumToString(tf));
      return false;
   }

   if(count <= 0)
      return false;

   MqlRates xau_rates[];
   MqlRates eur_rates[];
   int need = count + m_max_gap_bars;
   if(need < count)
      need = count; // overflow guard

   int xau_copied = m_rates_provider(SYNTH_LEG_XAUUSD, tf, 0, need, xau_rates);
   int eur_copied = m_rates_provider(SYNTH_LEG_EURUSD, tf, 0, need, eur_rates);

   if(xau_copied <= 0 || eur_copied <= 0)
   {
      Print("[Synthetic] Failed to copy M1 rates for XAUEUR legs");
      return false;
   }

   int xau_size = ArraySize(xau_rates);
   int eur_size = ArraySize(eur_rates);

   if(xau_size < count || eur_size < count)
   {
      PrintFormat("[Synthetic] Insufficient raw bars xau=%d eur=%d required=%d", xau_size, eur_size, count);
      return false;
   }

   // CopyRates returns series arrays (index 0 = most recent). We'll reorder by using helper loops.
   MqlRates xau_ordered[];
   MqlRates eur_ordered[];

   ArrayResize(xau_ordered, xau_size);
   ArrayResize(eur_ordered, eur_size);

   for(int i=0;i<xau_size;i++)
      xau_ordered[i] = xau_rates[xau_size - 1 - i];

   for(int j=0;j<eur_size;j++)
      eur_ordered[j] = eur_rates[eur_size - 1 - j];

   SyntheticBar built_bars[];
   int forward_filled = 0;
   if(!AlignRatesToBars(xau_ordered, xau_size, eur_ordered, eur_size, tf, count, built_bars, forward_filled))
      return false;

   int cache_index = FindCacheIndex(synthetic_symbol, tf);
   if(cache_index < 0)
   {
      cache_index = ArraySize(m_cache);
      ArrayResize(m_cache, cache_index + 1);
      m_cache[cache_index].symbol = synthetic_symbol;
      m_cache[cache_index].timeframe = tf;
      m_cache[cache_index].last_bar_time = 0;
      m_cache[cache_index].last_build_time = 0;
      m_cache[cache_index].valid = false;
      m_cache[cache_index].forward_filled_bars = 0;
      ArrayResize(m_cache[cache_index].bars, 0);
   }

   int bar_count = ArraySize(built_bars);
   ArrayResize(m_cache[cache_index].bars, bar_count);
   for(int k=0;k<bar_count;k++)
      m_cache[cache_index].bars[k] = built_bars[k];

   m_cache[cache_index].last_bar_time = built_bars[bar_count - 1].time;
   m_cache[cache_index].last_build_time = TimeCurrent();
   m_cache[cache_index].valid = true;
   m_cache[cache_index].forward_filled_bars = forward_filled;

   EnsureCacheCapacity();

   PrintFormat("[Synthetic] Cache rebuild %s %s count=%d forward_fill=%d", synthetic_symbol, EnumToString(tf), bar_count, forward_filled);
   if(forward_filled > 0)
      PrintFormat("[Synthetic] Forward-filled %d bars", forward_filled);

   return true;
}

bool SyntheticManager::GetCachedBars(const string synthetic_symbol, const ENUM_TIMEFRAMES tf, SyntheticBar &out[], const int count)
{
   if(count <= 0)
      return false;

   int index = FindCacheIndex(synthetic_symbol, tf);
   if(index < 0)
      return false;

   SyntheticCacheEntry entry = m_cache[index];
   if(!entry.valid)
      return false;

   int available = ArraySize(entry.bars);
   if(available < count)
      return false;

   if(entry.last_build_time < entry.last_bar_time)
      return false;

   int max_age_sec = PeriodSeconds(tf);
   if(max_age_sec <= 0)
      max_age_sec = 60;

   if(TimeCurrent() - entry.last_build_time > max_age_sec)
      return false;

   ArrayResize(out, count);
   int start_index = available - count;
   for(int i=0;i<count;i++)
      out[i] = entry.bars[start_index + i];

   PrintFormat("[Synthetic] Cache hit %s %s count=%d", synthetic_symbol, EnumToString(tf), count);
   return true;
}

void SyntheticManager::InvalidateCache(const string synthetic_symbol)
{
   int size = ArraySize(m_cache);
   for(int i=0;i<size;i++)
   {
      if(m_cache[i].symbol != synthetic_symbol)
         continue;
      m_cache[i].valid = false;
      m_cache[i].last_build_time = 0;
      m_cache[i].last_bar_time = 0;
      ArrayResize(m_cache[i].bars, 0);
   }
}

void SyntheticManager::InvalidateCache(const string synthetic_symbol, const ENUM_TIMEFRAMES tf)
{
   int index = FindCacheIndex(synthetic_symbol, tf);
   if(index < 0)
      return;
   m_cache[index].valid = false;
   m_cache[index].last_build_time = 0;
   m_cache[index].last_bar_time = 0;
   ArrayResize(m_cache[index].bars, 0);
}

void SyntheticManager::Clear()
{
   ArrayResize(m_cache, 0);
   ArrayResize(m_unsupported_logged, 0);
}

double SyntheticManager::ScaleSyntheticDistance(const double xaueur_distance, const double eurusd_rate) const
{
   if(eurusd_rate <= 0.0)
   {
      Print("[Synthetic] Scale distance aborted: invalid EURUSD rate");
      return 0.0;
   }

   double scaled = xaueur_distance * eurusd_rate;
   PrintFormat("[Synthetic] Scale distance xaueur=%.2f eurusd=%.5f scaled=%.2f", xaueur_distance, eurusd_rate, scaled);
   return scaled;
}

void SyntheticManager::SetTickProvider(SyntheticTickProvider provider)
{
   if(provider == NULL)
      provider = Synthetic_DefaultTickProvider;
   m_tick_provider = provider;
}

void SyntheticManager::SetRatesProvider(SyntheticRatesProvider provider)
{
   if(provider == NULL)
      provider = Synthetic_DefaultRatesProvider;
   m_rates_provider = provider;
}

void SyntheticManager::ResetProviders()
{
   m_tick_provider = Synthetic_DefaultTickProvider;
   m_rates_provider = Synthetic_DefaultRatesProvider;
}

//---------------------------------------------------------------------------
// Default providers
//---------------------------------------------------------------------------

bool Synthetic_DefaultTickProvider(const string symbol, MqlTick &out_tick)
{
   if(!SymbolSelect(symbol, true))
      return false;
   return SymbolInfoTick(symbol, out_tick);
}

int Synthetic_DefaultRatesProvider(const string symbol,
                                   const ENUM_TIMEFRAMES timeframe,
                                   const int start_pos,
                                   const int count,
                                   MqlRates &rates[])
{
   if(!SymbolSelect(symbol, true))
      return 0;
   return CopyRates(symbol, timeframe, start_pos, count, rates);
}

#endif // RPEA_SYNTHETIC_MQH
