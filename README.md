# Distance-to-Default-Model

# Naive Method

DDnaive ≡ (log(E + F/F) + (rit−1 − NaiveσV^2 /2)T)/NaiveσV *√T

where
NaiveσV = (E/E+F) *σE + (F / E + F) *(0.05 + 0.25 ∗ σE)

rit−1 is the firm’s stock return over the previous year

• explored the results using naive σD = (0.05 + 0.5 ∗ σE)

• explored the results using naive σD = (0.25 ∗ σE)

# Solving for Unknowns

E = V N (d1) − (e^(−r*T)) *F N (d2)

where
• E is the market value of the firm’s equity,

• F is the face value of the firm’s debt,

• r is the instantaneous risk-free rate,

• N (.) is the cumulative standard normal distribution function,

• d1 = (log(V/F) + (r + σV^2/T) )/ σV *√T

• d2 = d1 − σV * √T

In this model, the second equation, using an application of Ito’s lemma
and the fact that 

∂E / ∂V = N (d1), 

links the volatility of the firm value and the volatility of the equity.
σE = ( V / E ) *  N (d1) *σV

The unknowns in these two equations are
• the firm value V and

• the asset volatility σV .

The known quantities are
• equity value E,

• face value of debt or the default boundar

• risk-free interest rate r,

• time to maturity T.

Two nonlinear equations and two unknowns, we can directly solve for

V, σV

#KMV Model

Alternately, as in KMV model, we can iteratively solve for V, σV ,

• by starting with an initial value of σV ,

• using the equity option equation to solve for asset value V for the
sample period,

• construct the time-series of asset value and use this to compute the an
estimate of σV .

• This process is repeated till the value of σV converges.
