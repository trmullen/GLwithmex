m=int32(1968);
K=int32(13);
density=single(100);

[ A,b,partition,lambda ] = GenerateRandomGroupLassoDataSet( m,K,density );

disp(lambda);

MAX_ITER = int32(100);
ABSTOL   = single(1e-4);
RELTOL   = single(1e-2);

alpha=single(1);
rho=single(1);

g=gpuDevice();
disp('Device has compute capability ');
disp(g.ComputeCapability);
[m,n]=size(A);
m=int32(m);
n=int32(n);

u=single(zeros(n,1));
z=single(zeros(n,1));

do_obj=int32(0);
do_lam=int32(0);

lambda_counter=int32(0);
lambda_update_count=int32(10);
lambda_update_thresh=single(10^-5);

AA=A';
disp('partition sum= ');
dd=sum(partition);
disp(dd);
disp('m=');
disp(m);
disp('n=');
disp(n);
tic;
[nxtu,nxtz]=GroupMextest(AA,b,partition,u,z,rho,alpha,lambda,MAX_ITER,ABSTOL,RELTOL,do_obj,do_lam);% for this version matrix A must be passed in transpose (CUDA solver uses row major)
toc;
gtime=(toc-tic);
disp(gtime);


tic;

x = single(zeros(n,1));
% assuming that u and v are unchanged so will use them for both
% implementations
 
if (sum(partition) ~= n)
    error('invalid partition');
end
 
Atb = A'*b;
cum_part= int32(cumsum(double(partition)));

QUIET    = 1;
[L,U]=factor(A,rho);
 
for k = 1:MAX_ITER
       % x-update
    q = Atb + rho*(z - u);    % temporary value
    if( m >= n )    % if skinny
       x = U \ (L \ q);
    else            % if fat
       x = q/rho - (A'*(U \ ( L \ (A*q) )))/rho^2;
    end
 
    % z-update
    zold = z;
    start_ind = 1;
    x_hat = alpha*x + (1-alpha)*zold;
    for i = 1:length(partition),
        sel = start_ind:cum_part(i);
        z(sel) = shrinkage(x_hat(sel) + u(sel), lambda/rho);
        start_ind = cum_part(i) + 1;
    end
    u = u + (x_hat - z);
 
    % diagnostics, reporting, termination checks
    history.objval(k)  = objective(A, b, lambda, cum_part, x, z);
 
    history.r_norm(k)  = norm(x - z);
    history.s_norm(k)  = norm(-rho*(z - zold));
 
    history.eps_pri(k) = sqrt(single(n))*ABSTOL + RELTOL*max(norm(x), norm(-z));
    history.eps_dual(k)= sqrt(single(n))*ABSTOL + RELTOL*norm(rho*u);
 
 
   
    if ~QUIET
        fprintf('%3d\t%10.4f\t%10.4f\t%10.4f\t%10.4f\t%10.2f\n', k, ...
            history.r_norm(k), history.eps_pri(k), ...
            history.s_norm(k), history.eps_dual(k), history.objval(k));
    end
 
    if (history.r_norm(k) <history.eps_pri(k) && ...
       history.s_norm(k) <history.eps_dual(k))
         break;
    end
     if do_lam && k>1
        if  abs(history.r_norm(k)-history.r_norm(k-1)) < lambda_update_thresh ...
            && abs(history.s_norm(k)-history.s_norm(k-1)) < lambda_update_thresh
        
            lambda_counter = lambda_counter + 1;
            if lambda_counter > lambda_update_count
                lambda=lambda*single(0.1);
                lambda_counter=0;
            end
                    
        end
            
    end
    
end

% see the relative error between the pure MATLAB version and the CUDA GPU
% version interfaced through mex(in this small case there will be little
% difference, but when (m*n)>1e6 there will be a larger speedup with CUDA

toc;
ctime=(toc-tic);

disp(ctime);

disp('vector u diff');
disp(norm(nxtu-u));
disp('vector z diff');
disp(norm(nxtz-z));
disp('maxes');
disp(max(u));
disp(max(z));


    
