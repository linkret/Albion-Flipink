# Albion Flipink Trade Optimizer

This project analyzes and optimizes trading routes and item arbitrage in Albion Online using real market data.
The focus is on items with high daily trading volumes such as raw and refined materials, Luxury Goods items, and farming items.

## Quick Start

1. **Install Julia**  
   Download and install Julia from [https://julialang.org/downloads/](https://julialang.org/downloads/).  
   Make sure `julia` is available in your command line path.

2. **Clone the Repository**  
   ```sh
   git clone <your-repo-url>
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

## Notes

- Market data is fetched online and cached in the [`data`](data) folder.
- Large JSON files in [`data`](data) are ignored by git.
- You can customize the starting city, your silver budget, weight limit, and other parameters in the code!

---

**Enjoy earning millions of silver with your Albion Online transport routes!**
