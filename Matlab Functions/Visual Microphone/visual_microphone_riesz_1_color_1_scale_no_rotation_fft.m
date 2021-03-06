%test visual microphone algorithms:

%Initialize parameters:
image_file_name = 'barbara.tif';
low_cutoff_frequency = 200;
high_cutoff_frequency = 2000;
Fs = 5000;
phase_magnification_factor = 15;
flag_attenuate_other_frequencies = false;
smoothing_filter_sigma = 1.5; %seems much

%Get frame parameters: 
mat_in = imread(image_file_name);
mat_in_size = size(mat_in);
mat_in_padded = zeros(514,514);
mat_in_padded(2:513,2:513) = mat_in;
frame_height = mat_in_size(1);
frame_width = mat_in_size(2);
if length(mat_in_size) > 2
    number_of_channels = mat_in_size(3);
else
    number_of_channels = 1;
end
dyadic_partition_height = get_dyadic_partition_of_nondyadic_signals(frame_height);
dyadic_partition_width = get_dyadic_partition_of_nondyadic_signals(frame_width);
number_of_scales = 1; %number of scales to actually use

%Tmpoeral Filter parameters:
low_cutoff_frequency_normalized = low_cutoff_frequency/(Fs/2);
high_cutoff_Frequency_normalized = high_cutoff_frequency/(Fs/2);
%(1). FIR:
N = 1024;
bandpass_filter_object = get_filter_1D('kaiser',10,N,Fs,low_cutoff_frequency,high_cutoff_frequency,'bandpass'); %SWITCH!
bandpass_filter_numberator = bandpass_filter_object.Numerator;

%Get sound parameters:
number_of_seconds_to_check = 0.1; 
number_of_samples = round(Fs*number_of_seconds_to_check);
flag_sine_or_audio = 1; %1 or 2
if flag_sine_or_audio == 1
    Fc = 200;
    t_vec = my_linspace(0,1/Fs,number_of_samples);
    audio_vec = sin(2*pi*Fc*t_vec);
elseif flag_sine_or_audio == 2
    audio_file_name = 'bla.wav';
    [audio_vec,Fs_audio] = wavread(audio_file_name);
    audio_vec = resample(audio_vec,Fs,Fs_audio);
end


%% Get Riesz Pyramid Parameters:
%%%%%% CHOOSE WAY TO IMPLEMENT THE RIESZ TRANSFORM %%%%% :
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%(1). get image power spectrum to construct an ed-hok wavelet transform:
mat_in_fft = fft2(mat_in);
mat_in_power_spectrum = abs(mat_in_fft).^2;
% [ed_hok_riesz_wavelet_lowpass_impulse_response , ed_hok_riesz_wavelet_highpass_impulse_response] = ...
%                                     get_ed_hok_time_domain_riesz_wavelet_filters(mat_in_power_spectrum);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%(2). use Rubinstein's riesz pyramid transform:
[ filter_1D_lowpass_coefficients_rubinstein, ...
  filter_1D_highpass_coefficients_rubinstein, ...
  chebychev_polynomial_lowpass_rubinstein, ...
  chebychev_polynomial_highpass_rubinstein, ...
  McClellan_transform_matrix_rubinstein, ...
  filter_2D_lowpass_direct_rubinstein, ...
  filter_2D_highpass_direct_rubinstein ] = get_filters_for_riesz_pyramid();
filter_2D_lowpass_direct_rubinstein_fft = fft2(filter_2D_lowpass_direct_rubinstein,frame_height,frame_width);
filter_2D_highpass_direct_rubinstein_fft = fft2(filter_2D_highpass_direct_rubinstein,frame_height,frame_width);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%(2). use Generalized Riesz-Transform stuff:
isotropic_wavelet_types = {'simoncelli','shannon','aldroubi','papadakis','meyer','ward',...
                           'radial_rubinstein', 'radial_rubinstein_smoothed'};
prefilter_types = {'shannon','simoncelli','none'};
riesz_transform_order = 1;
%Riesz transform objects:
riesz_transform_configurations_object = riesz_transform_object(size(mat_in), 1, number_of_scales, 1);
wavelet_transform_configurations_object = riesz_transform_object(size(mat_in), 0, number_of_scales, 1);
%Riesz transform filters:
riesz_transform_fourier_filter_x = riesz_transform_configurations_object.riesz_transform_filters{1};
riesz_transform_fourier_filter_y = riesz_transform_configurations_object.riesz_transform_filters{2};
number_of_riesz_channels = riesz_transform_configurations_object.number_of_riesz_channels;
%%%% 
wavelet_type = 'isotropic'; %As opposed to 'spline', read paper to see why better
%%%%
mat_in_number_of_dimensions = 2;
max_real_space_support_for_fourier_defined_filters = 4; %[pixels] ONE SIDED (total size = 2*support+1)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%COMPUTE NORMALIZATION COEFFICIENTS:
%(*)compute riesz-wavelet coefficients for normalization:
%** ADD THIS CALCULATION IN THE ABOVE CALCULATION OF THE REFERENCE CELL ARRAY
delta_image = zeros(mat_in_size);
delta_image(1) = 1;
delta_image_fft = fft2(delta_image);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%PRE-CALCULATE LOWPASS AND HIGHPASS MASKS:
%the reason it was the in the downsampling loop is that the loop is
%intended for fourier space filtering, and so for each mat size a different
%mask is needed to be created. 
rows_dyadic_partition = get_dyadic_partition_of_nondyadic_signals(size(mat_in,1));
columns_dyadic_partition = get_dyadic_partition_of_nondyadic_signals(size(mat_in,2));
maskHP_fft = cell(1,number_of_scales);
maskLP_fft = cell(1,number_of_scales);
maskHP = cell(1,number_of_scales);
maskLP = cell(1,number_of_scales);
current_frame_height = frame_height;
current_frame_width = frame_width;
current_image_size = [current_frame_height,current_frame_width];
scale_counter = 1; %scale_counter is always 1 because here there's only 1 scale for this function
isotropic_wavelet_type = 'radial_rubinstein';
switch isotropic_wavelet_type,
    case 'meyer'
        [maskHP_fft{scale_counter} , maskLP_fft{scale_counter}] =  meyerMask(current_frame_height,current_frame_width, 2);
    case 'simoncelli',
        [maskHP_fft{scale_counter} , maskLP_fft{scale_counter}] =  simoncelliMask(current_frame_height,current_frame_width, 2);
    case 'papadakis',
        [maskHP_fft{scale_counter} , maskLP_fft{scale_counter}] =  papadakisMask(current_frame_height,current_frame_width, 2);
    case 'aldroubi',
        [maskHP_fft{scale_counter} , maskLP_fft{scale_counter}] =  aldroubiMask(current_frame_height,current_frame_width, 2);
    case 'shannon',
        [maskHP_fft{scale_counter} , maskLP_fft{scale_counter}] =  halfSizeEllipsoidalMask(current_frame_height,current_frame_width, 2);
    case 'ward',
        error('Wards wavelet function is not provided in this toolbox');
    case 'compact_rubinstein'
        maskHP{scale_counter} = filter_2D_highpass_direct_rubinstein;
        maskLP{scale_Counter} = filter_2D_lowpass_direct_rubinstein;
        maskHP_fft{scale_counter} = fft2(filter_2D_highpass_direct_rubinstein,current_frame_height,current_frame_width);
        maskLP_fft{scale_counter} = fft2(filter_2D_lowpass_direct_rubinstein,current_frame_height,current_frame_width);
    case 'radial_rubinstein'
        boundary_radiuses_between_adjacent_filters = 0.5; %half-band filter
        number_of_orientations = 8;
        transition_width = 0.75;
        [angle, log_rad] = get_polar_meshgrid([current_frame_height,current_frame_width]);
        [maskHP_fft{scale_counter}, maskLP_fft{scale_counter}] = ...
            get_radial_mask_pair(boundary_radiuses_between_adjacent_filters, log_rad, transition_width);
        maskHP{scale_counter} = ifft2(maskHP_fft{scale_counter});
        maskLP{scale_counter} = ifft2(maskLP_fft{scale_counter});
        maskHP_fft{scale_counter} = fftshift(maskHP_fft{scale_counter});
        maskLP_fft{scale_counter} = fftshift(maskLP_fft{scale_counter});
    case 'radial_rubinstein_smoothed' %doesn't look like half-band filters!!!!
        flag_complex_filter = true; % If true, only return filters in one half plane.
        cosine_order = 6;
        filters_per_octave = 6;
        pyramid_height = get_max_complex_steerable_pyramid_height(zeros([current_frame_height,current_frame_width]));
        [angle_meshgrid, radius_meshgrid] = get_polar_meshgrid([current_frame_height,current_frame_width]);
        radius_meshgrid = (log2(radius_meshgrid));
        radius_meshgrid = (pyramid_height+radius_meshgrid)/pyramid_height;
        number_of_filters = filters_per_octave*pyramid_height;
        radius_meshgrid = radius_meshgrid*(pi/2+pi/7*number_of_filters);
        angular_windowing_function = @(x, center) abs(x-center)<pi/2;
        radial_filters = {};
        count = 1;
        filters_squared_sum = zeros([current_frame_height,current_frame_width]);
        const = (2^(2*cosine_order))*(factorial(cosine_order)^2)/((cosine_order+1)*factorial(2*cosine_order));
        for k = number_of_filters:-1:1
            shift = pi/(cosine_order+1)*k+2*pi/7;
            radial_filters{count} = ...
                sqrt(const)*cos(radius_meshgrid-shift).^cosine_order .* angular_windowing_function(radius_meshgrid,shift);
            filters_squared_sum = filters_squared_sum + radial_filters{count}.^2;
            count = count + 1;
        end
        %Compute lopass residual:
        center = ceil((current_image_size+0.5)/2);
        lodims = ceil((center+0.5)/4);
        %We crop the sum image so we don't also compute the high pass:
        filters_squared_sum_cropped = filters_squared_sum(center(1)-lodims(1):center(1)+lodims(1) , ...
            center(2)-lodims(2):center(2)+lodims(2));
        low_pass = zeros(image_size);
        low_pass(center(1)-lodims(1):center(1)+lodims(1),center(2)-lodims(2):center(2)+lodims(2)) = ...
            abs(sqrt(1-filters_squared_sum_cropped));
        %Compute high pass residual:
        filters_squared_sum = filters_squared_sum + low_pass.^2;
        high_pass = abs(sqrt(1-filters_squared_sum));
        %If either dimension is even, this fixes some errors (UNDERSTAND WHY!!!):
        number_of_radial_filters = numel(radial_filters);
        if (mod(image_size(1),2) == 0) %even
            for k = 1:number_of_radial_filters
                temp = radial_filters{k};
                temp(1,:) = 0;
                radial_filters{k} = temp;
            end
            high_pass(1,:) = 1;
            low_pass(1,:) = 0;
        end
        if (mod(image_size(2),2) == 0)
            for k = 1:number_of_radial_filters
                temp = radial_filters{k};
                temp(:,1) = 0;
                radial_filters{k} = temp;
            end
            high_pass(:,1) = 1;
            low_pass(:,1) = 0;
        end
        maskLP_fft{scale_counter} = fftshift(low_pass);
        maskHP_fft{scale_counter} = fftshift(high_pass);
    otherwise
        error('unknown wavelet type. Valid options are: meyer, simoncelli, papadakis, aldroubi, shannon')
end %isotropic-wavelet type switch statement end 

if ~strcmp(isotropic_wavelet_type,'compact_rubinstein')
    %IFFT to get real space impulse response:
    temp_highpass = ifft2(maskHP_fft{scale_counter});
    temp_lowpass = ifft2(maskLP_fft{scale_counter});
    proper_indices_rows = current_frame_height/2+1-max_real_space_support_for_fourier_defined_filters : current_frame_height/2+1+max_real_space_support_for_fourier_defined_filters;
    proper_indices_columns = current_frame_width/2+1-max_real_space_support_for_fourier_defined_filters : current_frame_width/2+1+max_real_space_support_for_fourier_defined_filters;
    maskHP{scale_counter} = temp_highpass(proper_indices_rows,proper_indices_columns);
    maskLP{scale_counter} = temp_lowpass(proper_indices_rows,proper_indices_columns);
end



%Create double (3D) copies of the masks to allow efficient multiplying of the 3D riesz coefficients:
maskHP_3D = cell(1,number_of_scales);
maskLP_3D = cell(1,number_of_scales);
maskHP_3D_fft = cell(1,number_of_scales);
maskLP_3D_fft = cell(1,number_of_scales);
for scale_counter = 1:number_of_scales
    maskHP_3D{scale_counter} = repmat(maskHP{scale_counter},1,1,2);
    maskLP_3D{scale_counter} = repmat(maskLP{scale_counter},1,1,2);
    maskHP_3D_fft{scale_counter} = repmat(maskHP_fft{scale_counter}(:,:,1),1,1,2);
    maskLP_3D_fft{scale_counter} = repmat(maskLP_fft{scale_counter}(:,:,1),1,1,2);
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%(*) compute Riesz-wavelet coefficients:
    % PERHAPSE LOOK INTO AN AVERAGED IMAGE POWER SPECTRUM AND DESIGN A FILTER
    % WHICH TRIES TO DOWNPLAY NOISY FREQUENCIES.
    % OR MAYBE CONTINUE SOMEHOW THE LINE OF THOUGHT OF USING LOTS OF LOCAL
    % FILTERS AND WEIGH THEM APPROPRIATELY.
%(A). PREFILTEROF DIFFERENT  IMAGES:

%(1). Get prefilter filters (maybe use mat_in_fft or mat_in_spectrum!!!):
flag_use_perfilter = 1; %1 use prefilter, 0 don't
prefilter_type = 'simoncelli';
riesz_transform_prefilter_lowpass = riesz_transform_configurations_object.prefilter.filterLow;
riesz_transform_prefilter_highpass = riesz_transform_configurations_object.prefilter.filterHigh;

%(2). Filter mat_in:
mat_in_fft = fft2(mat_in);
if  flag_use_perfilter == 1
    mat_in_prefiltered = ifft2(mat_in_fft .* riesz_transform_prefilter_lowpass);
    mat_in_prefiltered_highpassed = ifft2(mat_in_fft .* riesz_transform_prefilter_highpass);
    delta_image_prefiltered = ifft2(delta_image_fft .* riesz_transform_prefilter_lowpass);
    delta_image_prefiltered_highpassed = ifft2(delta_image_fft .* riesz_transform_prefilter_highpass); 
else
    mat_in_prefiltered = mat_in;
    mat_in_prefiltered_highpassed = zeros(size(mat_in));
    delta_image_prefiltered = delta_image;
    delta_image_prefiltered_highpassed = zeros(size(delta_image));
end
mat_in_prefiltered_fft = fft2(mat_in_prefiltered);
delta_image_prefiltered_fft = fft2(delta_image_prefiltered);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%(B). PERFORM RIESZ-TRANSFORM TO CURRENT (PREFILTERED) IMAGE:
%(1). to mat_in:
%fourier space:
mat_in_riesz_coefficients_fft_3D = zeros(size(mat_in, 1), size(mat_in, 2), number_of_riesz_channels);
mat_in_riesz_coefficients_fft_3D(:,:,1) = mat_in_prefiltered_fft.*riesz_transform_fourier_filter_x;
mat_in_riesz_coefficients_fft_3D(:,:,2) = mat_in_prefiltered_fft.*riesz_transform_fourier_filter_y;
%direct space:
mat_in_riesz_coefficients_3D = zeros(size(mat_in, 1), size(mat_in, 2), number_of_riesz_channels);
mat_in_riesz_coefficients_3D(:,:,1) = real(ifft2(mat_in_riesz_coefficients_fft_3D(:,:,1)));
mat_in_riesz_coefficients_3D(:,:,2) = real(ifft2(mat_in_riesz_coefficients_fft_3D(:,:,2)));
%(2). to delta_image:
%fourier space:
delta_image_riesz_coefficients_fft_3D = zeros(size(mat_in, 1), size(mat_in, 2), number_of_riesz_channels);
delta_image_riesz_coefficients_fft_3D(:,:,1) = delta_image_prefiltered_fft.*riesz_transform_fourier_filter_x;
delta_image_riesz_coefficients_fft_3D(:,:,2) = delta_image_prefiltered_fft.*riesz_transform_fourier_filter_y;
%direct space:
delta_image_riesz_coefficients_3D = zeros(size(mat_in, 1), size(mat_in, 2), number_of_riesz_channels);
delta_image_riesz_coefficients_3D(:,:,1) = real(ifft2(delta_image_riesz_coefficients_fft_3D(:,:,1)));
delta_image_riesz_coefficients_3D(:,:,2) = real(ifft2(delta_image_riesz_coefficients_fft_3D(:,:,2)));
%Get normalization constants for riesz channels:
% stdNoiseRiesz = std(delta_image_riesz_coefficients_3D(:,:,1)); %normalization only acording to first channel
stdNoiseRiesz1 = delta_image_riesz_coefficients_3D(:,:,1);
stdNoiseRiesz2 = delta_image_riesz_coefficients_3D(:,:,2);
stdNoiseRiesz1 = std(stdNoiseRiesz1(:));
stdNoiseRiesz2 = std(stdNoiseRiesz2(:));
stdNoiseRiesz = sqrt(stdNoiseRiesz1.^2+stdNoiseRiesz2.^2);
stdNoiseWav = std(delta_image_prefiltered(:));
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%(E). GET ROTATION (ORIENTATION) ANGLES USING STRUCTURE TENSOR OR REGULAR METHOD:
flag_use_structure_tensor_or_regular_method_angles = 1; %1 or 2
if flag_use_structure_tensor_or_regular_method_angles == 1
                                                   
     %riesz transform parameters:
     smoothing_filter_sigma = 1.5; %seems much
     smoothing_filter_number_of_sigmas_to_cutoff = 4; 
     
     %compute the regularization kernel:
     smoothing_filter_axis_center = ceil(smoothing_filter_number_of_sigmas_to_cutoff*smoothing_filter_sigma) + 1;
     smoothing_filter_width = 2*ceil(smoothing_filter_number_of_sigmas_to_cutoff*smoothing_filter_sigma) + 1;
     smoothing_filter = zeros(smoothing_filter_width,smoothing_filter_width);
     for x1 = 1:smoothing_filter_width;
         for x2 = 1:smoothing_filter_width;
             smoothing_filter(x1, x2) = exp(-((x1-smoothing_filter_axis_center)^2 + (x2-smoothing_filter_axis_center)^2)...
                 / (2*smoothing_filter_sigma^2));
         end
     end
     %normalize:
     smoothing_filter = smoothing_filter/sum(smoothing_filter(:));
     
     % full range angle computation
     mat_in_wavelet_gradient_angle = mat_in_prefiltered;
     flag_restrict_angle_value = 1;
     if flag_restrict_angle_value == 1, %compute sign of the direction thanks to the gradient of the wavelet coefficients
         
         %Compute gradient of wavelet coefficients for different scales:
         %smooth current wavelet coefficients:
         %MAYBE ADD THAT INSTEAD OF IMFILTER USE A NEW FUNCTION WHICH DOES
         %convolve_without_end_effects BUT FOR 2D?!!?
         mat_in_wavelet_gradient_angle = imfilter(mat_in_wavelet_gradient_angle, smoothing_filter, 'symmetric');
         %Compute gradient for current scale wavelet:
         [FX,FY] = gradient(mat_in_wavelet_gradient_angle);
         
         %determine sign of the angle from the gradient:
         %(KIND OF WEIRD... WHY NOT ATAN2 AND THEN LOOK AT GRADIENT):
         mat_in_wavelet_gradient_angle = atan2(FY, FX);
     end
     
     %loop over the scales:
     scale_counter = 1;
     %compute the 4 Jmn maps:
     J11 = mat_in_riesz_coefficients_3D(:,:,1).^2;
     J12 = mat_in_riesz_coefficients_3D(:,:,1).*mat_in_riesz_coefficients_3D(:,:,2);
     J22 = mat_in_riesz_coefficients_3D(:,:,2).^2;
     
     %convolve the maps with the regularization kernel:
     J11 = imfilter(J11, smoothing_filter, 'symmetric');
     J12 = imfilter(J12, smoothing_filter, 'symmetric');
     J22 = imfilter(J22, smoothing_filter, 'symmetric');
     
     %compute the first eigenvalue table (UNDERSTAND WHY THIS ENABLES PHASE CALCULATION!!!):
     lambda1 = ( J22 + J11 + sqrt((J11-J22).^2 + 4*J12.^2) ) / 2;
     
     if flag_restrict_angle_value, %use the gradient to discriminate angles shifted by pi:
         rotation_angles = atan((lambda1-J11)./J12) + pi*(mat_in_wavelet_gradient_angle<0);
     else
         %compute the first eigen vector direction:
         rotation_angles = atan((lambda1-J11)./J12);
     end
                                                   
else %CALCULATE REGULAR METHOD, NOT STRUCTURE TENSOR
    
    rotation_angles = atan(mat_in_riesz_coefficients_3D{:}(:,:,2) ...
                                   ./ mat_in_riesz_coefficients_3D{:}(:,:,1));                          
end
cos_rotation_angles_original = cos(rotation_angles);
sin_rotation_angles_original = sin(rotation_angles);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



                                                                                                             
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%(G). COMPUTE PHASE AND AMPLITUDE:    
R1 = mat_in_riesz_coefficients_3D(:,:,1);
R2 = mat_in_riesz_coefficients_3D(:,:,2);
I = mat_in_prefiltered;
mat_in_phase = atan(sqrt(R1.^2+R2.^2)./I * stdNoiseWav/stdNoiseRiesz );
mat_in_amplitude = sqrt(R1.^2+R2.^2+I.^2);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 



%% TRY ALGORITHMS:
%**AFTERWARDS SEE HOW TO FILTER SIGNAL, WHETHER TO USE PHASE DIRECTLY OR TO
%  USE THE SUGGESTION IN THE RUBINSTEIN PAPER OF USING
%  [phi*cos(theta),phi*sin(theta)] or [sin(phi)*cos(theta),sin(phi)*sin(theta)]
%noise parameters:
optical_SNR = inf;
mat_in_signal_per_pixel = sum(mat_in(:))/numel(mat_in);
noise_std = mat_in_signal_per_pixel*(1/optical_SNR);

%Initialize initial noisy mat:
%(1). Normalize audio_vec:
max_shift_size = 10^-1; %[pixels]
audio_vec = audio_vec/max(abs(audio_vec))*max_shift_size;
%(2). Shift matrix to sample 1 position:
shift_angle = pi/4;
shift_size = audio_vec(1);
mat_in_padded = shift_matrix(mat_in_padded,1,shift_size*cos(shift_angle),shift_size*sin(shift_angle));
%(3). Add Noise for Initial image:
mat_in_padded_size = size(mat_in_padded);
noise_mat = noise_std * randn(mat_in_padded_size);
noisy_mat1 = mat_in_padded + noise_mat;
%(4). Initialize previous parameters:
R1_previous = R1;
R2_previous = R2;
I_previous = I;
%(5). Initialize matrix to remember phases over time:
phases_cos_over_time = zeros(size(mat_in,1),size(mat_in,2),number_of_samples);
phases_sin_over_time = zeros(size(mat_in,1),size(mat_in,2),number_of_samples);
phases_over_time = zeros(size(mat_in,1),size(mat_in,2),number_of_samples);
for sample_counter = 2:number_of_samples
    tic
    
    %Get current sample:
    shift_size = audio_vec(sample_counter); 
    
    %Initialize noisy mats:
    noisy_mat2 = shift_matrix(mat_in_padded,1,shift_size*cos(shift_angle),shift_size*sin(shift_angle));
    noise_mat = noise_std * randn(mat_in_padded_size);
    noisy_mat2 = noisy_mat2 + noise_mat;
    noisy_mat2 = real(noisy_mat2);
    
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    %Register images:
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %(A). PREFILTEROF DIFFERENT  IMAGES:
    mat_in = noisy_mat2(2:513,2:513);
    mat_in_fft = fft2(mat_in);
    if  flag_use_perfilter == 1
        mat_in_prefiltered = ifft2(mat_in_fft .* riesz_transform_prefilter_lowpass);
        mat_in_prefiltered_highpassed = ifft2(mat_in_fft .* riesz_transform_prefilter_highpass);
    else
        mat_in_prefiltered = mat_in;
        mat_in_prefiltered_highpassed = zeros(size(mat_in));
    end
    mat_in_prefiltered_fft = fft2(mat_in_prefiltered);
    mat_in_prefiltered = real(mat_in_prefiltered);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %(B). PERFORM RIESZ-TRANSFORM TO CURRENT (PREFILTERED) IMAGE:
    %(1). to mat_in:
    %fourier space:
    mat_in_riesz_coefficients_fft_3D = zeros(size(mat_in, 1), size(mat_in, 2), number_of_riesz_channels);
    mat_in_riesz_coefficients_fft_3D(:,:,1) = mat_in_prefiltered_fft.*riesz_transform_fourier_filter_x;
    mat_in_riesz_coefficients_fft_3D(:,:,2) = mat_in_prefiltered_fft.*riesz_transform_fourier_filter_y;
    %direct space:
    mat_in_riesz_coefficients_3D = zeros(size(mat_in, 1), size(mat_in, 2), number_of_riesz_channels);
    mat_in_riesz_coefficients_3D(:,:,1) = real(ifft2(mat_in_riesz_coefficients_fft_3D(:,:,1)));
    mat_in_riesz_coefficients_3D(:,:,2) = real(ifft2(mat_in_riesz_coefficients_fft_3D(:,:,2)));
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
       
     
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %(C). COMPUTE PHASE AND AMPLITUDE OF CURRENT IMAGE:
    R1 = mat_in_riesz_coefficients_3D(:,:,1);
    R2 = mat_in_riesz_coefficients_3D(:,:,2);
    I = mat_in_prefiltered;
    mat_in_phase = atan(sqrt(R1.^2+R2.^2)./I * stdNoiseWav/stdNoiseRiesz );
    amplitude_current = sqrt(R1.^2+R2.^2+I.^2);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %(D). CALCULATE PHASE DIFFERENCE BETWEEN CURRENT AND PREVIOUS FRAMES:
    flag_use_easy_method_or_phase_vector_method = 2; %1 or 2
    if flag_use_easy_method_or_phase_vector_method == 1
        %Get current times previous:
        q_conj_prod_real = I.*I_previous + ...
            R1.*R1_previous + ...
            R2.*R2_previous;
        q_conj_prod_x = -I.*R1_previous + I_previous.*R1;
        q_conj_prod_y = -I.*R2_previous + I_previous.*R2;
        %now we take the quaternioni logarithm of this.
        %only the imaginary part corresponds to quaternionic phase.
        q_conj_prod_amplitude = sqrt(q_conj_prod_real.^2 + q_conj_prod_x.^2 + q_conj_prod_y.^2);
        phase_difference = acos(q_conj_prod_real./q_conj_prod_amplitude);
        cos_orientation = q_conj_prod_x ./ sqrt(q_conj_prod_x.^2+q_conj_prod_y.^2);
        sin_orientation = q_conj_prod_y ./ sqrt(q_conj_prod_x.^2+q_conj_prod_y.^2);
        %this is the quaternionic phase:
        phase_difference_cos = phase_difference .* cos_orientation;
        phase_difference_sin = phase_difference .* sin_orientation;

        %under the assumption that changes are small between frames, we can
        %assume that the amplitude of both coefficients is the same. so, to
        %compute the amplitude of one coefficient, we just take the square root
        %of their conjugate product:
        mat_in_amplitude = sqrt(q_conj_prod_amplitude);
    elseif flag_use_easy_method_or_phase_vector_method == 2
        phase_difference_cos = phase_difference .* cos_rotation_angles_original;
        phase_difference_sin = phase_difference .* sin_rotation_angles_original;
        mat_in_amplitude = amplitude_current;
    end
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %(E). Use Amplitude-Weighting to phases:
    flag_filter_phase_difference_directly_or_quaternion = 1;
    amplitude_power_weight = 1;
    mat_in_amplitude_to_the_power = mat_in_amplitude.^amplitude_power_weight;
    if flag_filter_phase_difference_directly_or_quaternion == 1
        denominator = conv2(mat_in_amplitude_to_the_power, smoothing_filter);
        numerator = conv2(phase_difference.*mat_in_amplitude_to_the_power, smoothing_filter);
        amplitude_weighted_phase = numerator./denominator;
    else
        denominator = conv2(mat_in_amplitude_to_the_power, smoothing_filter);
        numerator1 = conv2(phase_difference_cos.*mat_in_amplitude_to_the_power, smoothing_filter);
        amplitude_weighted_phase_cos = numerator1./denominator;
        numerator2 = conv2(phase_difference_sin.*mat_in_amplitude_to_the_power, smoothing_filter);
        amplitude_weighted_phase_sin = numerator2./denominator;
    end
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
     
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %(F). Do Median filtering if wanted:
    flag_use_median_filtering = 0;
    median_filter_size = [3,3];
    if flag_use_median_filtering == 1
        if flag_filter_phase_difference_directly_or_quaternion == 1
            amplitude_weighted_phase = medfilt2(amplitude_weighted_phase,median_filter_size);
        else
            amplitude_weighted_phase_cos = medfilt2(amplitude_weighted_phase_cos,median_filter_size);
            amplitude_weighted_phase_sin = medfilt2(amplitude_weighted_phase_sin,median_filter_size);
        end
    end
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %(G). Keep track of phases over time:
    if flag_filter_phase_difference_directly_or_quaternion == 1
        amplitude_weighted_phase = amplitude_weighted_phase(median_filter_size:mat_in_size+median_filter_size-1, median_filter_size:mat_in_size+median_filter_size-1);
        phases_over_time(:,:,sample_counter) = amplitude_weighted_phase;
    elseif flag_filter_phase_difference_directly_or_quaternion == 2
        phases_cos_over_time(:,:,sample_counter) = amplitude_weighted_phase_cos(median_filter_size:mat_in_size+median_filter_size-1, median_filter_size:mat_in_size+median_filter_size-1);
        phases_sin_over_time(:,:,sample_counter) = amplitude_weighted_phase_sin(median_filter_size:mat_in_size+median_filter_size-1, median_filter_size:mat_in_size+median_filter_size-1);
    end
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%    
    
%Assign current frame to be previous frame:
    noisy_mat1 = noisy_mat2;
    R1_previous = R1;
    R2_previous = R2;
    I_previous = I;
    
    toc
end


%Get final signal:
for sample_counter = 1:number_of_samples
    
end















