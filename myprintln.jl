using Printf

# Custom print function that shows floats with all decimals instead of scientific notation
# It's otherwise identical to the default println() and implemented through it

function myprintln()
    println()
    return
end

function myprintln(x::Float64, xs...)
    @printf("%.2f", x)
    myprintln(xs...)
end

function myprintln(x, xs...)
    print(x)
    myprintln(xs...)
end