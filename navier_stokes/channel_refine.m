clear;close all;clc;

% D2Q9 solver
% Simple channel, with a carse-to-fine vertical grid interface in the 
% middle of the channel.
% West: fixed-velocity inlet
% North: wall
% South: wall 
% East: 0th-order-extrapolation outlet.

% We define a two grids; one fine and one coarse.
% The fine and coarse differ by only one level of refinement (4x cells).
% The fine and coarse grids overlap in one layer.
% The fine and coarse grids are both square.

% Physical parameters.
u_p = 0.01;
rho_p = 5;
L_p = 1; % Height of each channel.
nu_p = 1.568e-5; % kinematic viscosity, m^2/s.
% Grid parameters.
nodes_c = 100; % coarse nodes.
dt_c = 1; % coarse timestep.
timesteps = 2;
 
% Derived nondimensional parameters.
Re = u_p*L_p/nu_p;
disp(['Reynolds number: ' num2str(Re)]);
% Derived numerical parameters.
nodes_f = 2*nodes_c - 2;
dh_c = 1 / (nodes_c-1); % coarse spacing.
dh_f = dh_c / 2; % coarse spacing.
dt_f = dt_c / 2;
nu_lb_c = dt_c / dh_c^2 / Re; % coarse viscosity.
nu_lb_f = dt_f / dh_f^2 / Re; % fine viscosity.
tau_c = 3*nu_lb_c + 0.5; % coarse relaxation time.
tau_f = 3*nu_lb_f + 0.5; % fine relaxation time.
omega_c = 1 / ( 3*tau_c + 0.5 );
omega_f = 1 / ( 3*tau_f + 0.5 );
u_lb_c = dh_c / dt_c;
u_lb_f = dh_f / dt_f;

% Initialize.
rho_c = rho_p*ones(nodes_c,nodes_c);
rho_f = rho_p*ones(nodes_f,nodes_f);
u_c = u_lb_c*ones(nodes_c,nodes_c);
u_f = u_lb_f*ones(nodes_f,nodes_f);
v_c = zeros(nodes_c,nodes_c);
v_f = zeros(nodes_f,nodes_f);
f_c = zeros(nodes_c,nodes_c,9);
f_f = zeros(nodes_f,nodes_f,9);
% Wall BCs.
u_c(1,:) = 0;
v_c(1,:) = 0;
u_c(end,:) = 0;
v_c(end,:) = 0;
u_f(1,:) = 0;
v_f(1,:) = 0;
u_f(end,:) = 0;
v_f(end,:) = 0;

% Main loop.
reconstruction_time = 0;
collision_time = 0;
streaming_time = 0;
bc_time = 0;
for iter = 1:timesteps
    disp(['Running timestep ' num2str(iter)]);
    % First, we explode coarse cells and map to fine.
    u_f = explode_column(u_c,u_f);
    v_f = explode_column(v_c,v_f);
    rho_f = explode_column(rho_c,rho_f);
    for k = 1:9
        f_f(:,:,k) = explode_column(f_c(:,:,k), f_f(:,:,k));
    end
    % Second, we iterate on fine cells.
    for k = 1:2
        % Stream.
        tic;
        f_f = stream(f_f);
        streaming_time = streaming_time + toc;
        % Collide.
        tic;
        f_f = collide(f_f,u_f,v_f,rho_f,omega_f);
        collision_time = collision_time + toc;
        % BCs.
        tic;
        f_f = outlet_bc(f_f,'east');
        f_f = wall_bc(f_f,'south');
        f_f = wall_bc(f_f,'north');
        u_f(1,:) = 0;
        v_f(1,:) = 0;
        u_f(end,:) = 0;
        v_f(end,:) = 0;
        bc_time = bc_time + toc;
        % Density and velocity reconstruction.
        tic;
        [u_f, v_f, rho_f] = reconstruct_macro(f_f, u_f, v_f);
%         rho(end,2:end) = f(end,2:end,1) + f(end,2:end,2) + f(end,2:end,4) + ...
%             2*( f(end,2:end,3) + f(end,2:end,7) + f(end,2:end,6) );
%         u(2:end-1,2:end) = 0;
%         v(2:end-1,2:end) = 0;
%         for k = 1:9
%             u(2:end-1,2:end) = u(2:end-1,2:end) + c(k,1)*f(2:end-1,2:end,k);
%             v(2:end-1,2:end) = v(2:end-1,2:end) + c(k,2)*f(2:end-1,2:end,k);
%         end
%         u(2:end-1,2:end) = u(2:end-1,2:end) ./ rho(2:end-1,2:end);
%         v(2:end-1,2:end) = v(2:end-1,2:end) ./ rho(2:end-1,2:end);
        reconstruction_time = reconstruction_time + toc;
    end
    % Third, we stream on coarse.
    tic;
    f_c = stream(f_c);
    streaming_time = streaming_time + toc;
    % Fourth, coalesce to coarse.
    for k = [4, 7, 8]
        f_c(1,end,k) = 0.5 * ( f_f(1,1,k) + f_f(1,2,k) );
        f_c(2:end-1,end,k) = 0.25 * (...
            f_f(2:2:end-1,1,k) + f_f(3:2:end-1,1,k)...
            + f_f(2:2:end-1,2,k) + f_f(3:2:end-1,2,k) );
        f_c(end,end,k) = 0.5 * ( f_f(end,1,k) + f_f(end,2,k) );
    end
    % Fifth, collide on coarse.
    tic;
    f_c = collide(f_c,u_c,v_c,rho_c,omega_c);
    collision_time = collision_time + toc;
    % Coarse BC.
    tic;
    f_c = inlet_bc(f_c, u_lb_c, 'west');
    f_c = wall_bc(f_c,'south');
    f_c = wall_bc(f_c,'north');
    u_c(1,:) = 0;
    v_c(1,:) = 0;
    u_c(end,:) = 0;
    v_c(end,:) = 0;
    u_c(:,1) = u_lb_c;
    bc_time = bc_time + toc;
    % Density and velocity reconstruction.
    tic;
    [u_c, v_c, rho_c] = reconstruct_macro(f_c, u_c, v_c);
    reconstruction_time = reconstruction_time + toc;
end

% Timing outputs.
total_time = reconstruction_time + collision_time + streaming_time + bc_time;
disp(['Solution reconstruction time (s): ' num2str(reconstruction_time)]);
disp(['Collision time (s): ' num2str(collision_time)]);
disp(['Streaming time (s): ' num2str(streaming_time)]);
disp(['BC time (s): ' num2str(bc_time)]);
disp(['Solution reconstruction fraction: ' num2str(reconstruction_time/total_time)]);
disp(['Collision fraction: ' num2str(collision_time/total_time)]);
disp(['Streaming fraction: ' num2str(streaming_time/total_time)]);
disp(['BC fraction: ' num2str(bc_time/total_time)]);

% Streamfunction calculation.
strf_c = streamfunction(u_c,v_c,rho_c);
strf_f = streamfunction(u_f,v_f,rho_f);

% Plotting results!
x_c = linspace(0,1,nodes_c)';
y_c = linspace(0,1,nodes_c)';
[X_c, Y_c] = meshgrid(x_c,y_c);
figure;
contour(X_c(2:end,2:end), Y_c(2:end,2:end), strf_c(2:end,2:end));
title('Coarse solution');
xlabel('x');
ylabel('y');
x_f = linspace(0,1,nodes_f)';
y_f = linspace(0,1,nodes_f)';
[X_f, Y_f] = meshgrid(x_f,y_f);
figure;
contour(X_f(2:end,2:end), Y_f(2:end,2:end), strf_f(2:end,2:end));
title('Fine solution');
xlabel('x');
ylabel('y');



