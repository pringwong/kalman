real_frequency = .42;         % Hz
real_phase     = deg2rad(15); % radians
real_amplitude = 2;           % <scalar>
real_offset    = -5;          % <scalar>
real_carrier_freq = 0.0125;   % Hz

T_start        = 0;           % seconds
T_end          = 20;          % seconds
N_samples      = 500;         % <number of samples>

% generate the time vector
time_vector = linspace(T_start, T_end, N_samples);
 
% generate the data vector
real_omega = 2*pi*real_frequency;
real_carrier = cos(2*pi*real_carrier_freq*time_vector);
real_data = real_amplitude*sin(real_omega*time_vector+real_phase) + real_offset + real_carrier;

% generate the output buffers
observed_data = nan(1, N_samples);
estimated_output = nan(1, N_samples);
estimated_state = nan(4, N_samples);

% plot the real data
close all;
plot(time_vector, real_data, 'k');
xlabel('t [s]');
ylabel('a*sin(\omegat+\phi)+b');

% "it it is easier to approximate
%  a probability distribution than it is to approximate
%  an arbitrary nonlinear function or transformation"
% J. K. Uhlmann, �Simultaneous map building and localization for
% real time applications,� transfer thesis, Univ. Oxford, Oxford, U.K.,
% 1994.

kappa = 1;
alpha = 1;
beta = 2;

% set initial state estimate
x = [
     0;   % angle [rad]    
     .5;  % frequency [Hz]
     1;   % amplitude [<scalar>]
     -2]; % offset [<scalar>]
 
% set initial state covariance
P = 100*diag(ones(size(x)));
 
% define additive state covariance prediction noise
R = 1e-1 * ...
    [deg2rad(10) 0  0  0;        % angle
     0  1 0  0;                  % frequency
     0  0  .01 0;                % amplitude
     0  0  0  .10];              % offset

% define additive measurement covariance prediction noise
z_sigma = 0.05;
Q = [z_sigma 0;
     0 1e-2];

% simulate
h = waitbar(0, 'Simulating ...');
for i=1:N_samples;
   
    % obtain current time and time delta to last step
    t = time_vector(i);
    if i > 1
        T = t-time_vector(i-1);
    else
        T = 0;
    end
        
    % define the nonlinear state transition function
    state_transition_fun = @(x) [x(1) + 2*pi*x(2)*T;
                                 x(2); x(3); x(4)];

    % define the nonlinear observation function
    % note this is time dependent
    observation_fun = @(x) [x(3)*sin(x(1) + 2*pi*x(2)*T)+x(4);  % expected output
                            real_carrier(i)];                   % expected carrier
   
    % time update - propagate state
    [x_prior, P_prior, X, Xwm, Xwc] = unscented(state_transition_fun, ...
                                                x, P, ...
                                                'n_out', 4, ...
                                                'alpha', alpha, ...
                                                'beta', beta, ...
                                                'kappa', kappa);

    % "enforce" symmetry
    % P_prior = (.5*P_prior) + (.5*P_prior');
                                            
    % add prediction noise
    P_prior = P_prior + R;
        
    % predict observations using the a-priori state
    % Note that the weights calculated by this function are the very
    % same as calculated above since we're still operating on 
    % the state vector (i.e. dimensionality didn't change).
    [z_estimate, S_estimate, Z] = unscented(observation_fun, ...
                                            x_prior, P_prior, ...
                                            'n_out', 2, ...
                                      	    'alpha', alpha, ...
                                            'beta', beta, ...
                                            'kappa', kappa);
    
    if mod(i,floor(10*rand(1))) ~= 0
        % pass variables around
        estimated_output(i) = z_estimate(1);
        x = x_prior;
        P = P_prior;
    else
        % add measurement noise Q to S_estimate
        S_estimate = S_estimate + Q;

        % calculate state-observation cross-covariance
        Pxy = zeros(numel(x), numel(z_estimate));
        for j=1:numel(Xwc)
            Pxy = Pxy + Xwc(j)*(X(:,j)-x_prior)*(Z(:,j)-z_estimate)';
        end

        % calculate Kalman gain
        K = Pxy/S_estimate; % note the inversion of S!

        % obtain observation
        z_error = z_sigma*randn(1);
        z = [real_data(i) + z_error;
             real_carrier(i)];

        % measurement update
        x_posterior = x_prior + K*(z - z_estimate);
        P_posterior = P_prior - K*S_estimate*K';

        % pass variables around
        z_posterior = observation_fun(x_posterior);
        estimated_output(i) = z_posterior(1);
        observed_data(i) = z(1);
        x = x_posterior;
        P = P_posterior;
    end

    % store estimated state
    estimated_state(:,i) = x;
    
    % update the progress bar
    waitbar(i / N_samples, h);
    
end

% remove the progress bar
delete(h); 

% plot the estimated data
hold all;
valid = ~isnan(estimated_output);
plot(time_vector(valid), estimated_output(valid), 'r', 'LineWidth', 1);
plot(time_vector(valid), observed_data(valid), 'm+');

% plot the state estimate
figure;
subplot(4,1,1);
plot(time_vector, ones(1,N_samples)*real_frequency, 'k'); hold on;
plot(time_vector, estimated_state(1,:), 'r');
xlabel('t [s]');
ylabel('\phi [rad]');

subplot(4,1,2);
plot(time_vector, ones(1,N_samples)*real_phase, 'k'); hold on;
plot(time_vector, estimated_state(2,:), 'r');
xlabel('t [s]');
ylabel('f [Hz]');

subplot(4,1,3);
plot(time_vector, ones(1,N_samples)*real_amplitude, 'k'); hold on;
plot(time_vector, estimated_state(3,:), 'r');
xlabel('t [s]');
ylabel('amplitude');

subplot(4,1,4);
plot(time_vector, real_offset + cos(2*pi*real_carrier_freq*time_vector), 'k'); hold on;
plot(time_vector, estimated_state(4,:), 'r');
xlabel('t [s]');
ylabel('offset');