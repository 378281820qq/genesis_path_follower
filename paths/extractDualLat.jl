# code to test and extract dual multipliers from primal solution
# GXZ + MB

using MAT
using Gurobi
using JuMP



#### problem paramters for LONGITUDINAL Control 
# Global variable LOAD_PATH contains the directories Julia searches for modules when calling require. It can be extended using push!:
push!(LOAD_PATH, "../scripts/mpc_utils") 	
import GPSKinMPCPathFollowerFrenetLinLatGurobi
import KinMPCParams
const kmpcLinLat = GPSKinMPCPathFollowerFrenetLinLatGurobi  # short-hand-notation


# Load as Many parameters as possible from MPC file to avoid parameter mis-match
N 		= KinMPCParams.N
dt 		= KinMPCParams.dt
nx 		= 2								# dimension of x = (ey,epsi)
nu 		= 1								# number of inputs u = df
L_a 	= KinMPCParams.L_a				# from CoG to front axle (according to Jongsang)
L_b 	= KinMPCParams.L_b				# from CoG to rear axle (according to Jongsang)


n_uxu 	= kmpcLinLat.n_uxu
H_gurobi = kmpcLinLat.H_gurobi
f_gurobi_init = kmpcLinLat.f_gurobi_init
ub_gurobi = kmpcLinLat.ub_gurobi
lb_gurobi = kmpcLinLat.lb_gurobi

## Load Ranges of params 
 ey_lb = KinMPCParams.ey_lb
 ey_ub = KinMPCParams.ey_ub
 epsi_lb = KinMPCParams.epsi_lb
 epsi_ub = KinMPCParams.epsi_ub
 dfprev_lb = -KinMPCParams.df_max
 dfprev_ub =  KinMPCParams.df_max

 v_lb = KinMPCParams.v_min 
 v_ub = KinMPCParams.v_max
 curv_lb = KinMPCParams.curv_lb
 curv_ub = KinMPCParams.curv_ub
 

############## load all data ##############
# latData = matread("NN_test_trainingData.mat")

# # inputParam_lat = np.hstack((ey_curr.T, epsi_curr.T ,df_prev.T, v_pred, c_pred))
# inputParam_lat = latData["inputParam_lat"]   #
# outputParamDf_lat = latData["outputParamDf_lat"]
# outputParamDdf_lat = latData["outputParamDdf_lat"]

# parse initial data
# ey_curr_all = inputParam_lat[:,1]
# epsi_curr_all = inputParam_lat[:,2]
# df_prev_all = inputParam_lat[:,3]
# v_pred_all = inputParam_lat[:,4:4+N-1]
# c_pred_all = inputParam_lat[:,12:end]

### Load MPC data ###
x_tilde_lb = kmpcLinLat.x_tilde_lb
x_tilde_ub = kmpcLinLat.x_tilde_ub
u_tilde_lb = kmpcLinLat.u_tilde_lb
u_tilde_ub = kmpcLinLat.u_tilde_ub

Q_tilde = kmpcLinLat.Q_tilde
R_tilde = kmpcLinLat.R_tilde

nu_tilde = kmpcLinLat.nu_tilde
nx_tilde = kmpcLinLat.nx_tilde

Q_tilde_vec = kron(eye(N),Q_tilde)   # for x_tilde_vec
R_tilde_vec = kron(eye(N),R_tilde)	 # for u_tilde_vec

u_ref_init = kmpcLinLat.u_ref_init	# if not used, set cost to zeros
x_tilde_ref_init = kmpcLinLat.x_tilde_ref_init

Fu_tilde = [eye(nu) ; -eye(nu)]
fu_tilde = [u_tilde_ub; -u_tilde_lb]
ng = length(fu_tilde)
# Concatenate input (tilde) constraints
Fu_tilde_vec = kron(eye(N), Fu_tilde)
fu_tilde_vec = repmat(fu_tilde,N)

# Appended State constraints (tilde)
F_tilde = [eye(nx+nu) ; -eye(nx+nu)]
f_tilde = [x_tilde_ub ; -x_tilde_lb]
nf = length(f_tilde);
# Concatenate appended state (tilde) constraints
F_tilde_vec = kron(eye(N), F_tilde)
f_tilde_vec = repmat(f_tilde,N)   

######################## ITERATE OVER saved parameters ################
# build problem
num_DataPoints = 10								# Training data count 
solv_time_all = zeros(num_DataPoints)
# df_res_all = zeros(num_DataPoints)
# ddf_res_all = zeros(num_DataPoints)
dual_gap = zeros(num_DataPoints)
dual_gapRel = zeros(num_DataPoints)
optVal_long = zeros(num_DataPoints)

inputParam_lat = zeros(num_DataPoints,3+2*N)
outputParamDual_lat = zeros(num_DataPoints, N*(nf+ng))
outputParamDf_lat = zeros(num_DataPoints, N*(nu))
outputParamDdf_lat  = zeros(num_DataPoints, N*(nu))

status = []
statusD = []

# used to debug
# obj_diff = zeros(num_DataPoints)
# obj_diffRel = zeros(num_DataPoints)
# df_res_all2 = zeros(num_DataPoints)
# ddf_res_all2 = zeros(num_DataPoints)

# counts number of errors when solving the optimization problems
primStatusError = 0
dualStatusError = 0

dual_Fx = []
dual_Fu = []
L_test_opt = []
ii = 1

while ii <= num_DataPoints	
	
	# Save only feasible points. 
	# extract appropriate parameters	
 	ey_0 = ey_lb + (ey_ub-ey_lb)*rand(1)				
 	epsi_0 = epsi_lb + (epsi_ub-epsi_lb)*rand(1) 
 	u_0 = dfprev_lb + (dfprev_ub-dfprev_lb)*rand(1) 		
	v_pred = v_lb + (v_ub-v_lb)*rand(1,N)						#  Along horizon 
	c_pred = curv_lb + (curv_ub-curv_lb)*rand(1,N)				#  Along horizon 
 	
	# df_stored = outputParamDf_lat[ii,:]
	# ddf_stored = outputParamDdf_lat[ii,:]

	# build problem (only the updated parts)
	x0 = [ey_0 ; epsi_0]
	u0 = u_0 				# it's really u_{-1}
	x_tilde_0 = [x0 ; u0]	# initial state of system; PARAMETER

	# system dynamics A, B, g
	A_updated = zeros(nx, nx, N)
	B_updated = zeros(nx, nu, N)
	g_updated = zeros(nx, N)
	for i = 1 : N
		A_updated[:,:,i] = [	1	dt*v_pred[i] 
								0		1			]
		B_updated[:,:,i] = [	dt*v_pred[i]*L_b/(L_a+L_b) 
								dt*v_pred[i]/(L_a + L_b)	]
		g_updated[:,i] = [ 0	# column vector
						-dt*v_pred[i]*c_pred[i] 	]
	end
	
	# x_tilde transformation
	# update system matrices for tilde-notation
	A_tilde_updated = zeros(nx+nu,nx+nu,N)
	B_tilde_updated = zeros(nx+nu,nu,N)
	g_tilde_updated = zeros(nx+nu,N)
	for i = 1 : N 
		A_tilde_updated[:,:,i] = [ 	A_updated[:,:,i]  		B_updated[:,:,i] 
									zeros(nu,nx)   			eye(nu)			]
		B_tilde_updated[:,:,i] = [	B_updated[:,:,i] 	;  	eye(nu)	]
		g_tilde_updated[:,i] =   [	g_updated[:,i]		; 	zeros(nu) ]
	end

	# need to build A_tilde_vec, B_tilde_vec, E_tilde_vec
	A_tilde_vec = zeros(N*(nx+nu), (nx+nu))
	A_tmp = eye(nx+nu)  	# tmp variable used to store the ``powers of A_tilde"
	for ii = 1 : N
		A_tmp = A_tilde_updated[:,:,ii]*A_tmp
	    A_tilde_vec[1+(ii-1)*(nx+nu):ii*(nx+nu),:] = A_tmp 	#A_tilde^ii
	end

	B_tilde_vec = zeros(N*(nx+nu), nu*N)
	for ii = 0 : N-1
	    for jj = 0 : ii-1
	    	A_tmp = eye(nx+nu)	# used to emulate A_tilde^(ii-jj)
	    	for kk = 1 : (ii-jj)
	    		A_tmp = A_tilde_updated[:,:,kk+1]*A_tmp
	    	end
	        B_tilde_vec[1+ii*(nx+nu):(ii+1)*(nx+nu), 1+jj*nu:  (jj+1)*nu] = A_tmp*B_tilde_updated[:,:,jj+1] 	# A_tilde^(ii-jj)*B_tilde
	    end
	    B_tilde_vec[1+ii*(nx+nu):(ii+1)*(nx+nu), 1+ii*nu:(ii+1)*nu] = B_tilde_updated[:,:,ii+1]
	end

	nw=nx+nu
	E_tilde_vec = zeros(N*(nx+nu), nw*N)
	for ii = 0 : N-1
	    for jj = 0 : ii-1
	    	A_tmp = eye(nx+nu) 	# simulates A_tilde^(ii-jj)
	    	for kk = 1 : (ii-jj)
	    		A_tmp = A_tilde_updated[:,:,kk+1]*A_tmp
	    	end
	        E_tilde_vec[1+ii*(nx+nu):(ii+1)*(nx+nu), 1+jj*nw:  (jj+1)*nw] = A_tmp * eye(nx+nu)    # A_tilde^(ii-jj)*eye(nx+nu)
	    end
	    E_tilde_vec[1+ii*(nx+nu):(ii+1)*(nx+nu), 1+ii*nw:(ii+1)*nw] = eye(nx+nu)
	end

	g_tilde_vec = zeros(N*(nx+nu))
	for ii = 1 : N
		g_tilde_vec[1+(ii-1)*(nx+nu) : ii*(nx+nu)] = g_tilde_updated[:,ii]
	end

	x_tilde_ref = x_tilde_ref_init
	mdl = Model(solver=GurobiSolver(Presolve=0, LogToConsole=0))
	@variable(mdl, x_tilde_vec[1:N*(nx+nu)])  	# decision variable; contains everything
	@variable(mdl, u_tilde_vec[1:N*nu] )
	@objective(mdl, Min, (x_tilde_vec-x_tilde_ref)'*Q_tilde_vec*(x_tilde_vec-x_tilde_ref) + u_tilde_vec'*R_tilde_vec*u_tilde_vec)
	constr_eq = @constraint(mdl, x_tilde_vec .== A_tilde_vec*x_tilde_0 + B_tilde_vec*u_tilde_vec + E_tilde_vec*g_tilde_vec)
	constr_Fx = @constraint(mdl, F_tilde_vec*x_tilde_vec .<= f_tilde_vec)
	constr_Fu = @constraint(mdl, Fu_tilde_vec*u_tilde_vec .<= fu_tilde_vec)

	tic()
	status = solve(mdl)
	
	if !(status == :Optimal)
		println(status)
		primStatusError = primStatusError+1
		@goto label1
	end

	#### extract dual variables ####
	### seems to be wrong 
	# dual_eq = getdual(constr_eq)
	# dual_Fx = getdual(constr_Fx)
	# dual_Fu = getdual(constr_Fu)
	# dual_ineq = [dual_Fx; dual_Fu]


	#### get dual variables ###
	Q_dual = 2*(B_tilde_vec'*Q_tilde_vec*B_tilde_vec + R_tilde_vec);
     
    c_dual = (2*x_tilde_0'*A_tilde_vec'*Q_tilde_vec*B_tilde_vec + 2*g_tilde_vec'*E_tilde_vec'*Q_tilde_vec*B_tilde_vec +
    	      - 2*x_tilde_ref'*Q_tilde_vec*B_tilde_vec)'
     
    const_dual = x_tilde_0'*A_tilde_vec'*Q_tilde_vec*A_tilde_vec*x_tilde_0 + 2*x_tilde_0'*A_tilde_vec'*Q_tilde_vec*E_tilde_vec*g_tilde_vec +
                  + g_tilde_vec'*E_tilde_vec'*Q_tilde_vec*E_tilde_vec*g_tilde_vec +
                  - 2*x_tilde_0'*A_tilde_vec'*Q_tilde_vec*x_tilde_ref - 2*g_tilde_vec'*E_tilde_vec'*Q_tilde_vec*x_tilde_ref +
                  + x_tilde_ref'*Q_tilde_vec*x_tilde_ref
        
    C_dual = [F_tilde_vec*B_tilde_vec; Fu_tilde_vec]		        # Adding state constraints 
    d_dual = [f_tilde_vec - F_tilde_vec*A_tilde_vec*x_tilde_0 - F_tilde_vec*E_tilde_vec*g_tilde_vec;  fu_tilde_vec]
    Qdual_tmp = C_dual*(Q_dual\(C_dual'))
    Qdual_tmp = 0.5*(Qdual_tmp+Qdual_tmp') + 0e-5*eye(N*(nf+ng))

	# Solve the dual problem online to match cost 
    mdlD = Model(solver=GurobiSolver(Presolve=0, LogToConsole=0))
	@variable(mdlD, L_test[1:N*(nf+ng)])  	# decision variable; contains everything
	@objective(mdlD, Max, -1/2 * L_test'*Qdual_tmp*L_test - (C_dual*(Q_dual\c_dual)+d_dual)'*L_test - 1/2*c_dual'*(Q_dual\c_dual) + const_dual)
	@constraint(mdlD, -L_test .<= 0)

	statusD = solve(mdlD)
	
	if !(statusD == :Optimal)
		println(statusD)
		dualStatusError = dualStatusError+1
		@goto label1
	end

	inputParam_lat[ii,:] = [ey_0 epsi_0 u_0 v_pred c_pred]

	obj_primal = getobjectivevalue(mdl)
	obj_primal1 = obj_primal
	optVal_long[ii] = obj_primal
	solv_time_all[ii] = toq()

	x_tilde_vec_opt = getvalue(x_tilde_vec)
	ddf_pred_opt = getvalue(u_tilde_vec)
	df_pred_opt = x_tilde_vec_opt[3:nx+nu:end]

	## store the primal solution too as output gonna change now 
	outputParamDf_lat[ii,:]   = df_pred_opt
	outputParamDdf_lat[ii,:]  = ddf_pred_opt
 	###########################################################	


	# #### compare solution ####
	# df_res_all[ii] = norm(df_pred_opt - df_stored)
	# ddf_res_all[ii] = norm(ddf_pred_opt - ddf_stored)


	obj_dualOnline = getobjectivevalue(mdlD)

	# extract solution
	L_test_opt = getvalue(L_test)
	outputParamDual_lat[ii,:] = L_test_opt

	dual_gap[ii] = (obj_primal - obj_dualOnline)
	dual_gapRel[ii] = (obj_primal-obj_dualOnline)/obj_primal
	

###########################

	# # z-transformation
	# Aeq_gurobi_updated = zeros(N*nx_tilde , N*(nx_tilde+nu_tilde))
	# Aeq_gurobi_updated[1:nx_tilde, 1:(nx_tilde+nu_tilde)] = [-B_tilde_updated[:,:,1] eye(nx_tilde)] 	# fill out first row associated with x_tilde_1
	# for i = 2 : N  	# fill out rows associated to x_tilde_2, ... , x_tilde_N
	# 	Aeq_gurobi_updated[ (i-1)*nx_tilde+1 : i*nx_tilde  , (i-2)*(nu_tilde+nx_tilde)+(nu_tilde)+1 : (i-2)*(nu_tilde+nx_tilde)+nu_tilde+(nx_tilde+nu_tilde+nx_tilde)    ] = [-A_tilde_updated[:,:,i] -B_tilde_updated[:,:,i] eye(nx_tilde)]
	# end

	# # right-hand-size of equality constraint
	# beq_gurobi_updated = zeros(N*nx_tilde)
	# for i = 1 : N
	# 	beq_gurobi_updated[(i-1)*nx_tilde+1:i*nx_tilde] = g_tilde_updated[:,i]
	# end
	# beq_gurobi_updated[1:nx_tilde] = beq_gurobi_updated[1:nx_tilde] + A_tilde_updated[:,:,1]*x_tilde_0 	# PARAMETER: depends on x0



	# Solve optimization problem
	# ================== recall Transformation 2 ======================
	# bring into GUROBI format
	# minimize_z    z' * H * z + f' * z
		# s.t.		A_eq * z = b_eq
					# A * z <= b
					# z_lb <= z <= z_ub

	# mdl = Model(solver=GurobiSolver(Presolve=0, LogToConsole=0))
	# @variable(mdl, z[1:N*n_uxu])  	# decision variable; contains everything
	# @objective(mdl, Min, z'*H_gurobi*z + f_gurobi_init'*z)
	# constr_eq = @constraint(mdl, Aeq_gurobi_updated*z .== beq_gurobi_updated)
	# constr_ub = @constraint(mdl, z .<= ub_gurobi)
	# constr_lb = @constraint(mdl, -z .<= -lb_gurobi)

	# tic()
	# status = solve(mdl)
	# solv_time_all[ii] = toq()
	# obj_primal2 = getobjectivevalue(mdl)

	# obj_diff[ii] = norm(obj_primal1-obj_primal2)
	# obj_diffRel[ii] = norm(obj_primal1-obj_primal2)/norm(obj_primal2)

	# # extract solution
	# z_opt = getvalue(z)
	# 	# structure of z = [ (ddf,ey,epsi,df) ; (ddf, ey, epsi, df) ; ... ]
	# ddf_pred_opt2 = z_opt[1:n_uxu:end]
	# df_pred_opt2 = z_opt[4:n_uxu:end]
	# ey_pred_opt2 = z_opt[2:n_uxu:end]  	# does not include s0
	# epsi_pred_opt2 = z_opt[3:n_uxu:end] 		# does not include v0 

	# df_res_all2[ii] = norm(df_pred_opt2 - df_stored)
	# ddf_res_all2[ii] = norm(ddf_pred_opt2 - ddf_stored)


	# #### extract dual variables ####
	# dual_eq = getdual(constr_eq)
	# dual_ub = getdual(constr_ub)
	# dual_lb = getdual(constr_lb)

	# outputParamDualEQ_lat[ii,:] = dual_eq
	# outputParamDualLB_lat[ii,:] = dual_ub
	# outputParamDualUB_lat[ii,:] = dual_ub

	ii = ii+1 

	@label label1

	println("Index: $(ii)")
end

println("****************************")
println("primal status errors:  $(primStatusError)")
println("dual status errors:  $(dualStatusError)")

# println("max obj_diff (difference btw Trafo1 and Trafo2): $(maximum(obj_diff))")
# println("max Rel obj_diff (difference btw Trafo1 and Trafo2): $(maximum(obj_diffRel))")
# println("max df-residual2:  $(maximum(df_res_all2))")
# println("max ddf-residua2l:  $(maximum(ddf_res_all2))")

# println("max df-residual:  $(maximum(df_res_all))")
# println("max ddf-residual:  $(maximum(ddf_res_all))")
# println("max solv-time (excl modelling time):  $(maximum(solv_time_all[2:end]))")
# println("avg solv-time (excl modelling time):  $(mean(solv_time_all[2:end]))")
println("max dual_gap:  $(maximum(dual_gap))")
println("min dual_gap:  $(minimum(dual_gap))")
println("max Rel dual_gap:  $(maximum(dual_gapRel))")
println("min Rel dual_gap:  $(minimum(dual_gapRel))")

# matwrite("NN_test_trainingDataLat_PrimalDual.mat", Dict(
# 	"inputParam_lat" => inputParam_lat,
# 	"outputParamDf_lat" => outputParamDf_lat,
# 	"outputParamDdf_lat" => outputParamDdf_lat,
# 	"outputParamDual_lat" => outputParamDual_lat
# ))
# println("---- done extracting and saving dual for LAT control ----")
