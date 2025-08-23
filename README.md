# Albion Flipink Trade Optimizer

This project analyzes and optimizes trading routes and item arbitrage in Albion Online using real market data from ['The Albion Online Data Project'](https://www.albion-online-data.com/).
The focus is on items with high liquidity such as raw and refined materials, Luxury Goods items, and farming items, so that they sell quickly.

## Quick Start

1. **Install Julia**  
   Download and install Julia from [https://julialang.org/downloads/](https://julialang.org/downloads/).  
   Make sure `julia` is available in your command line path.

2. **Clone the Repository**  
   ```sh
   git clone git@github.com:linkret/Albion-Flipink.git
   cd Albion Flipink
   ```

3. **Install Dependencies**  
   Start Julia in your project folder:
   ```sh
   julia
   ```
   Then activate the project and install packages:
   ```julia
   using Pkg
   Pkg.activate(".")
   Pkg.instantiate()
   ```

4. **Run the Optimizer**  
   In the Julia REPL, run:
   ```julia
   include("trade_optimizer.jl")
   ```
   The script will fetch market data, run optimizations, and output results.

## Output

- Results are printed to the terminal.
- Detailed best trade scenario is saved to [`best_trade_details.txt`](best_trade_details.txt).
- Note: if the best trade scenario is a cyclical 3-city route, the output format is unfinished. So if it says:
      ```
      Optimal trade quantities for Thetford → Fort Sterling → Lymhurst:
      T2_PLANKS: AB = 2000, AC = 100, BC = 300
      ...
     	```
     This means to buy 2100 T2 Planks in city A (Thetford), sell 2000 T2 Planks in city B (Fort Sterling), and buy 300 T2 Planks in city B, then sell the last 400 T2 Planks in city C (Lymhurst).
     This format will be improved, to be as pretty and as verbose as in a 2-city trade scenario.

## Notes

- Market data is fetched online and cached in the [`data`](data) folder.
- Large JSON files in [`data`](data) are ignored by git.
- You can customize the starting city, your silver budget, weight limit, and other parameters in the code!

---

**Enjoy earning millions of silver with your Albion Online transport routes!**
