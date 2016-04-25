# Initial clean-up
rm(list=ls())

# Load packages
library("rodeo")
library("readxl")
library("deSolve")

################################################################################
# Adjustable settings

fileTbl <- "def_tables.xlsx"           # workbook with model declaration
fileFun <- "def_functions.f95"         # functions implemented in Fortran

u <- 1                                 # advective velocity (m/s)
d <- 30                                # longit. dispersion coefficient (m2/s)
wetArea <- 50                          # wet cross-section area (m2)
dx <- 10                               # length of a sub-section (m)
nCells <- 1000                         # number of sub-sections
inputCell <- 100                       # index of sub-section with tracer input
inputMass <- 10                        # input mass (g)
times <- c(0,30,60,600,1800,3600)      # times of interest (seconds)

# End of settings
################################################################################

# Proper time vector; first element must be 0
times <- sort(unique(c(0, times)))

# Initialize rodeo object
model <- new("rodeo", vars=read_excel(fileTbl, "vars"),
  pars=read_excel(fileTbl, "pars"), funs=read_excel(fileTbl, "funs"),
  pros=read_excel(fileTbl, "pros"), stoi=read_excel(fileTbl, "stoi"),
  asMatrix=TRUE)

# Numerical dispersion for backward finite-difference approx. of advection term
dNum <- u*dx/2

# Maximum integration time step according to Courant and Neumann criteria
# Note: In practice, a less strict constaint often works well and saves time.
dtMax_Courant <- dx/u
dtMax_Neumann <- dx^2/2/d
dtMax <- 0.5 * min(dtMax_Courant, dtMax_Neumann)

# Assign initial values and parameters
v <- model$arrangeVars(list(
  c=ifelse((1:nCells)==inputCell, inputMass/wetArea/dx, 0)
))
p <- model$arrangePars(list(
  leftmost= c(1, rep(0, nCells-1)), rightmost= c(rep(0, nCells-1), 1),
  u=u, d=d-dNum, dx=dx
))

# Generate code, compile into shared library, load library
lib <- model$compile(fileFun, NLVL=nCells)              
dyn.load(lib["libFile"])

# Integrate
solNum <- ode(y=v, times=times, func=lib["libFunc"], parms=p,
  dllname=lib["libName"], initfunc="initmod", hmax=dtMax,
  nout=model$lenPros()*nCells, jactype="bandint", bandup=1, banddown=1)

# Function providing the analytical solution
solAna <- function (x,t,m,a,d,u) {
  m/a/sqrt(4*3.141593*d*t) * exp(-((x-u*t)^2) / (4*d*t))
}

# Plots to compare numerical and analytical solution 
nc <- 2
nr <- ceiling(length(times) / nc)
layout(matrix(1:(nc*nr), ncol=nc, byrow=TRUE))
par(mar=c(4,4,1,1))
for (t in times) {
  plot(c(0,nCells*dx), c(1e-7,inputMass/wetArea/dx), type="n", xlab="Station (m)",
    ylab="g/m3", log="y")
  # Numeric solution (stair steps of cell-average)
  stations <- seq(from=0, by=dx, length.out=nCells+1)
  concs <- solNum[solNum[,1]==t, paste0("c.",1:nCells)]
  lines(stations, c(concs,concs[length(concs)]), type="s", col="steelblue4")
  # Analytical solution (for center of cells)
  stations <- seq(from=dx/2, to=(nCells*dx)-dx/2, by=dx)
  concs <- solAna(x=stations, t=t, m=inputMass, a=wetArea, d=d, u=u)
  stations <- stations + (inputCell*dx) - dx/2
  lines(stations, concs, col="red", lty=2)
  # Extra
  abline(v=(inputCell*dx) - dx/2, lty=3)
  legend("topright", bty="n", paste("After",t,"sec"))
  if (t == times[1]) legend("right",lty=1:2,
    col=c("steelblue4","red"),legend=c("Numeric", "Exact"),bty="n")
}
layout(1)

# Clean-up
dyn.unload(lib["libFile"])
invisible(file.remove(lib["libFile"]))

