%test_PM_demodulator_with_click_threshold:

% function [] = simple_PM_demodulator(directory,file_name,flag_bin_or_wav,flag_save_to_wav,flag_sound_demodulation,multiplication_factor)
%simple PM demodulator based on dsp objects:
% clear all;
file_name='sivsol_adasha oneway_far pc_tray_windy';
directory='C:\Users\master\Desktop\matlab';
flag_save_to_wav=1;
flag_sound_demodulation=1;

file_name_with_bin = strcat(file_name,'.bin');
full_file_name = fullfile(directory,file_name_with_bin);

 
try
    fclose(fid); 
    release(audio_player_object); 
    release(audio_file_writer_demodulated);
    release(audio_file_reader);
    release(analytic_signal_object);  
    fclose('all');
catch 
end

%audio reader object:
fid = fopen(full_file_name,'r');
number_of_elements_in_file = fread(fid,1,'double');
Fs = fread(fid,1,'double');
final_Fs_to_sound = 44000;
down_sample_factor = round(Fs/final_Fs_to_sound);
Fs_downsampled = Fs/down_sample_factor;


%Decide on number of samples per frame:
% time_for_FFT_frame = 0.045; %10[mSec]
% counts_per_time_frame = round(Fs*time_for_FFT_frame);
% samples_per_frame = counts_per_time_frame;
samples_per_frame = 2048;
global_to_sub_frame_size_ratio = 40;
samples_per_frame_demodulation = samples_per_frame * global_to_sub_frame_size_ratio;
number_of_frames_in_file = floor(number_of_elements_in_file/samples_per_frame);
number_of_seconds_in_file = floor(number_of_elements_in_file/Fs);

%Default Initial Values:
flag_PM_or_FM=1;
if flag_PM_or_FM==1
   PM_FM_str='PM'; 
else
   PM_FM_str='FM';
end
 
%analytic signal object:
analytic_signal_object = dsp.AnalyticSignal;
analytic_signal_object.FilterOrder=100;

%basic filter parameters:
carrier_filter_parameter = 10;
signal_filter_parameter = 10;
carrier_filter_length = 128*1; 
signal_filter_length = 128*6; 
%signal filter: 
filter_name_signal = 'hann';
signal_filter_type = 'bandpass';
signal_start_frequency = 150;
signal_stop_frequency = 3000;
[signal_filter] = get_filter_1D(filter_name_signal,signal_filter_parameter,signal_filter_length,Fs_downsampled,signal_start_frequency,signal_stop_frequency,signal_filter_type);
signal_filter_object = dsp.FIRFilter('Numerator',signal_filter.Numerator);    
signal_filter_object2 = dsp.FIRFilter('Numerator',signal_filter.Numerator);
signal_filter_object3 = dsp.FIRFilter('Numerator',signal_filter.Numerator);

%carrier filter:
Fc = 12000; %initial Fc
BW = signal_stop_frequency*2;
filter_name_carrier = 'hann';
f_low_cutoff_carrier = Fc-BW/2;
f_high_cutoff_carrier = Fc+BW/2;
carrier_filter_type = 'bandpass';
[carrier_filter] = get_filter_1D(filter_name_carrier,carrier_filter_parameter,carrier_filter_length,Fs,f_low_cutoff_carrier,f_high_cutoff_carrier,carrier_filter_type);
carrier_filter_object = dsp.FIRFilter('Numerator',carrier_filter.Numerator);


%save demodulation to wav file if wanted:
if flag_save_to_wav==1
    audio_file_writer_demodulated = dsp.AudioFileWriter;
    audio_file_writer_demodulated.Filename = strcat(fullfile(directory,file_name),'  ' , PM_FM_str ,' final demodulated audio ', ' ', num2str(signal_start_frequency),'-',num2str(signal_stop_frequency),'[Hz]'...
        ,'audacity1.wav');
    audio_file_writer_demodulated.SampleRate = 44100;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%NOISE REMOVAL STUFF:

%Frame parameters:
overlap_samples_per_frame = (samples_per_frame * 1/2);	
non_overlapping_samples_per_frame = samples_per_frame - overlap_samples_per_frame ;
hanning_window = make_column(hanning(samples_per_frame));
enhanced_speech_overlapped_samples_from_previous_frame = zeros(overlap_samples_per_frame,1);

%Input Constant Parameters:
noise_attenuation_in_dB = -10;
sensitivity_in_dB = 6; 
frequency_smoothing_BW_in_Hz = 0;
number_of_frequency_bins = round(frequency_smoothing_BW_in_Hz/(1/(samples_per_frame/Fs)));
% number_of_frequency_bins = 4;
attack_time = 0.02; 
release_time = 0.1; 
spectral_minimum_search_time = 0.05;
sensitivity_factor = 10^(sensitivity_in_dB/10);
noise_attenuation_factor = 10^(noise_attenuation_in_dB/20);
spectral_floor_factor = 0.05;

%Noise reduction Parameters:
number_of_frequency_smoothing_bins = round((frequency_smoothing_BW_in_Hz/(Fs/2)) * (samples_per_frame/2));
attack_decay_number_of_samples = attack_time*Fs;
attack_decay_number_of_blocks = 1 + round( attack_decay_number_of_samples / (samples_per_frame/2) );
attack_decay_per_block = 10^( noise_attenuation_in_dB/(20*attack_decay_number_of_blocks) );
release_decay_number_of_samples = release_time*Fs;
release_decay_number_of_blocks = 1 + round( release_decay_number_of_samples / (samples_per_frame/2) );
release_decay_per_block = 10^( noise_attenuation_in_dB/(20*release_decay_number_of_blocks) );
spectral_minimum_search_number_of_blocks = round( spectral_minimum_search_time * Fs / (samples_per_frame/2) );
spectral_minimum_search_number_of_blocks = max( 2 , spectral_minimum_search_number_of_blocks );
gains_history_number_of_blocks = attack_decay_number_of_blocks + release_decay_number_of_blocks - 1; 
gains_history_number_of_blocks = max(gains_history_number_of_blocks,spectral_minimum_search_number_of_blocks);

%Search window history indices:
center_of_spectral_minimum_history_blocks = release_decay_number_of_blocks;
start_of_spectral_minimum_history_blocks = center_of_spectral_minimum_history_blocks - floor(spectral_minimum_search_number_of_blocks/2);
stop_of_spectral_minimum_history_blocks = center_of_spectral_minimum_history_blocks + ceil(spectral_minimum_search_number_of_blocks/2);

%Initialize Matrices containing spectrums and gains history:
spectrums_history = zeros(gains_history_number_of_blocks,samples_per_frame);
ffts_history = zeros(gains_history_number_of_blocks,samples_per_frame);
gains_history = ones(gains_history_number_of_blocks,samples_per_frame) * noise_attenuation_factor;

%Get initial noise-only number of initial seconds:
number_of_initial_seconds_containing_only_noise = 3;
number_of_initial_samples_containing_only_noise = round(Fs*number_of_initial_seconds_containing_only_noise);

%Initialize needed variables:
first_and_seoncd_greatest_spectrums = zeros(2,samples_per_frame);
global_spectrum_max = zeros(1,samples_per_frame);
initial_noise_data_spectrum_matrix_running_local_min = zeros(spectral_minimum_search_number_of_blocks,samples_per_frame);
first_and_second_greatest_spectrums = zeros(2,samples_per_frame);
last_phase_previous = 0;
noise_gate_threshold_vec = zeros(1,samples_per_frame);
current_sub_frame = zeros(samples_per_frame,1);
current_max_sample = 0;
last_cumsum = 0;

%FFT & IFFT objects:
FFT_object = dsp.FFT;
IFFT_object = dsp.IFFT;
signal_buffer_object = dsp.Buffer;
signal_buffer_object.Length = samples_per_frame;
signal_buffer_object.OverlapLength = overlap_samples_per_frame;


%audio player object:
audio_player_object = dsp.AudioPlayer;
audio_player_object.SampleRate=44100;
audio_player_object.QueueDuration = 5;

%Get detector frequency calibration:
load('detector_frequency_calibration');
x_frequency = f_vec;
y_frequency = fft_sum_smoothed;
x_calibration = fft_get_frequency_vec(samples_per_frame_demodulation,Fs,0);
y_calibration = interp1(x_frequency,y_frequency,x_calibration); 

%Jump to start_second:
start_second = 5; 
stop_second = start_second+25;
stat_second = max(start_second,0);
stop_second = min(stop_second,number_of_seconds_in_file);
number_of_frames_to_read = floor((stop_second-start_second)*Fs/samples_per_frame_demodulation);
fseek(fid,8*ceil(start_second*Fs),-1);

frame_counter=1;
flag_skip_initial_delay = 1;
phase_signal_difference = zeros(samples_per_frame_demodulation,1);
% profile on;
while frame_counter<number_of_frames_to_read
    tic
 
    %Read current sub-frame and use signal_buffer_object to get overlapping frames:
    current_frame = fread(fid,samples_per_frame_demodulation,'double');
    
%     %Adjust frequencies according to detector calibration:
%     current_fft = fftshift(fft(current_frame));
%     current_fft = current_fft./y_calibration';
%     current_frame = real(ifft(fftshift(current_fft)));
    
    %filter carrier:
    flag_filter_carrier = 1;
    if flag_filter_carrier == 1
        filtered_carrier = step(carrier_filter_object,current_frame);
    else
        filtered_carrier = current_frame;
    end
    
    %extract analytic signal:
    analytic_signal = step(analytic_signal_object,filtered_carrier);
    
    %USE DAN'S DEMODULATINO METHOD:
    %(1). creating relevant t_vec:
    current_t_vec = (frame_counter-1)*(samples_per_frame_demodulation/Fs) + (0:samples_per_frame_demodulation-1)/Fs;
    %(2). multiply by proper phase term to get read of most of carrier:
    analytic_signal_after_carrier_removal = analytic_signal.*exp(-1i*2*pi*Fc*current_t_vec');
    %(3). Turn analytic signal to FM:
    phase_signal_difference(2:end) = angle(analytic_signal_after_carrier_removal(2:end).*conj(analytic_signal_after_carrier_removal(1:end-1)));
    
    %Fill phase signal to full length:
    first_phase_current = angle(analytic_signal_after_carrier_removal(1));
    phase_signal_difference(1) = first_phase_current-last_phase_previous;
    last_phase_previous = angle(analytic_signal_after_carrier_removal(end));
    
    %Set thresholds and Build masks:
    click_threshold = 0.0008; %silence where analytic signal amplitude is below this threshold
    indices_to_disregard_click = find( abs(analytic_signal_after_carrier_removal) < click_threshold );
         
    %Remove Clicks options:
    flag_use_only_found_only_additional_or_both = 3;
    additional_indices_to_interpolate_over = indices_to_disregard_click;
    number_of_indices_around_spikes_to_delete_as_well = 0;
    flag_use_my_spline_or_matlabs_or_binary_or_do_nothing = 3;
    
    %(5). Remove clicks:
    flag_use_despiking_or_just_my_mask_or_nothing = 1;
    if flag_use_despiking_or_just_my_mask_or_nothing == 1
        [phase_signal_after_mask,indices_containing_spikes,~] = despike_SOL_fast_with_logical_masks(phase_signal_difference, flag_use_only_found_only_additional_or_both, additional_indices_to_interpolate_over, number_of_indices_around_spikes_to_delete_as_well, flag_use_my_spline_or_matlabs_or_binary_or_do_nothing); 
    elseif flag_use_despiking_or_just_my_mask_or_nothing == 2
        phase_signal_after_mask = phase_signal_difference.*analytic_signal_mask;
        phase_signal_after_mask = phase_signal_after_mask.*phase_signal_mask;
    elseif flag_use_despiking_or_just_my_mask_or_nothing == 3
        phase_signal_after_mask = phase_signal_difference;
    end
 
    %Smooth signal from spikes
    binary_mask = ones(samples_per_frame_demodulation,1);
    binary_mask(indices_containing_spikes)=0;
    raw_signal_weights = (abs(analytic_signal).^1).*binary_mask;
    derivative_signal_weight_coefficient = 4;
    differentiation_order = 2;
    [phase_signal_after_mask] = smooth_lsq_minimum_iterations_with_preweights(phase_signal_difference,raw_signal_weights,derivative_signal_weight_coefficient,differentiation_order);
     
%     phase_signal_after_mask = phase_signal_difference(:);
    %(6). down sample:
%     phase_signal_after_mask = downsample(phase_signal_after_mask(:),down_sample_factor);

    %(7). filter demodulated signal:
%     filtered_phase = step(signal_filter_object,phase_signal_after_mask(:));
    filtered_phase = phase_signal_after_mask(:); 
    current_buffered_matrix = buffer(filtered_phase,samples_per_frame,overlap_samples_per_frame);
    current_buffered_matrix = abs(fft(current_buffered_matrix)).^2;
    current_sub_frames_median = median(current_buffered_matrix,2);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%    
    %START NOISE REMOVAL PROCEDURE:
    minimum_frame_counter_to_start_noise_removal = 1;
    if frame_counter>=minimum_frame_counter_to_start_noise_removal
        start_index = 1;
        stop_index = overlap_samples_per_frame;
        sub_frame_counter = 1;
        while sub_frame_counter < global_to_sub_frame_size_ratio*2
            %Current sample count:
%             current_max_sample = (2*(frame_counter-1)+sub_frame_counter) * overlap_samples_per_frame;
            
            %disregard first few sub frames because of system objects delay:
            if flag_skip_initial_delay==1
                %zero flag to not enter condition again:
                flag_skip_initial_delay = 0;
                
                %skip sub_frame_counter*overlap_samples_per_frame into the signal:
                initial_sub_frame_skip = 3;
                sub_frame_counter = initial_sub_frame_skip+1; 
                start_index = overlap_samples_per_frame*(sub_frame_counter-1)+1;
                stop_index = overlap_samples_per_frame*(sub_frame_counter);
                %put next two subframes into "current_sub_frame": 
                current_sub_frame = filtered_phase(start_index:start_index+2*overlap_samples_per_frame-1);
                %shift current positions in accordance with us initializing current_sub_frame:
                current_max_sample = overlap_samples_per_frame*2;
                start_index = start_index + overlap_samples_per_frame*2;
                stop_index = stop_index + overlap_samples_per_frame*2; 
                sub_frame_counter = sub_frame_counter+2;
                current_max_sample = current_max_sample + overlap_samples_per_frame;
            else
                %shift current_sub_frame memory:
%                 current_sub_frame = [current_sub_frame(overlap_samples_per_frame+1:end);filtered_phase(start_index:stop_index)];
                current_sub_frame = step(signal_buffer_object,filtered_phase(start_index:stop_index));
                current_max_sample = current_max_sample + overlap_samples_per_frame;
                %Uptick filtered phase indices:
                start_index = start_index + overlap_samples_per_frame;
                stop_index = stop_index + overlap_samples_per_frame;
                sub_frame_counter = sub_frame_counter+1; 
            end 
             
            %Get current frame fft, magnitude, phase and spectrum:
            current_sub_frame = current_sub_frame.*hanning_window;
            current_frame_fft = step(FFT_object,current_sub_frame);  
            current_frame_spectrum = abs(current_frame_fft).^ 2;
            
            %Update histories:
            ffts_history(1,:) = current_frame_fft;
            spectrums_history(1,:) = current_frame_spectrum;
            gains_history(1,:) = noise_attenuation_factor;
            current_search_window_spectrums = spectrums_history(start_of_spectral_minimum_history_blocks:stop_of_spectral_minimum_history_blocks,:);
            current_sorted_search_window_spectrums = sort(current_search_window_spectrums,1);
            current_mean_search_window_spectrums = mean(current_search_window_spectrums,1);

            %Either:
            %(1). Update Noise Profile:
            noise_profile_flag = 3;
            if current_max_sample < number_of_initial_samples_containing_only_noise
                if noise_profile_flag==1
                    %average power spectrum:
                    noise_gate_threshold_vec = (noise_gate_threshold_vec*(frame_counter-1) + current_frame_spectrum) / frame_counter;
                elseif noise_profile_flag==2
                    %max of min:
                    initial_noise_data_spectrum_matrix_running_local_min(1,:) = current_frame_spectrum;
                    initial_noise_data_spectrum_matrix_running_local_min = circshift(initial_noise_data_spectrum_matrix_running_local_min,1);
                    initial_noise_data_spectrum_running_max_of_min = min(initial_noise_data_spectrum_matrix_running_local_min,[],1);

                    %find global max of running max of min
                    global_spectrum_max = max( global_spectrum_max , initial_noise_data_spectrum_running_max_of_min );

                    %Assign max of min to noise gate thresholds:
                    noise_gate_threshold_vec = global_spectrum_max;
                elseif noise_profile_flag==3
                    %get second greatest:
                    indices_to_update_first_greatest = find(current_frame_spectrum>first_and_second_greatest_spectrums(1,:)');
                    indices_to_update_second_greatest = find(current_frame_spectrum<first_and_second_greatest_spectrums(1,:)' & current_frame_spectrum>first_and_second_greatest_spectrums(2,:)');
                    first_and_second_greatest_spectrums(1,indices_to_update_first_greatest) = current_frame_spectrum(indices_to_update_first_greatest);
                    first_and_second_greatest_spectrums(2,indices_to_update_second_greatest) = current_frame_spectrum(indices_to_update_second_greatest);
                    noise_gate_threshold_vec = first_and_second_greatest_spectrums(2,:);
                end
            end
            noise_gate_threshold_vec = current_sub_frames_median';
            %(2). Reduce Noise:
            if current_max_sample > number_of_initial_samples_containing_only_noise
                %raise the gain for elements in the center of the sliding history:
                %(*) The assumption is that at first all indices are BELOW noise gate,
                %and it is only when an index is found to be above the gate (according
                %to our criteria) that we change something and raise the center index
                %to 1, which then decays according to our rules.
                %(*) If current history is found not to be above noise gate then it is
                %passed through WITHOUT CHANGE, and so it can be effected by both
                %forward frames and backward frames WHICH CAN ONLY RAISE(!) IT

                noise_classification_flag_counter=1;
                if noise_classification_flag_counter==1
                    %check if second greatest in search window is above noise threshold
                    indices_above_noise_gate = find(current_sorted_search_window_spectrums(round(size(current_sorted_search_window_spectrums,1)/2),:) > sensitivity_factor * noise_gate_threshold_vec);

                elseif noise_classification_flag_counter==2
                    %check if current window mean is above noise threshold
                    indices_above_noise_gate = find(current_mean_search_window_spectrums > sensitivity_factor * noise_gate_threshold_vec');
                end
                if ~isempty(indices_above_noise_gate)
                    gains_history(center_of_spectral_minimum_history_blocks, indices_above_noise_gate) = 1;
                end

                %DECAY THE GAIN IN BOTH DIRECTIONS:
                %(*) if the gain before or after is lower then what one gets when we decay the current center gain
                % then RAISE it according to decay rate from center gain:
                %ATTACK/HOLD (backward in time):
                for history_frame_counter = center_of_spectral_minimum_history_blocks+1 : 1 : gains_history_number_of_blocks
                    gains_history(history_frame_counter,:) = max( gains_history(history_frame_counter-1,:)*attack_decay_per_block, max(noise_attenuation_factor*ones(1,samples_per_frame),gains_history(history_frame_counter,:)) );
                end
                %RELEASE (forward in time):
                for history_frame_counter = center_of_spectral_minimum_history_blocks-1 : -1 : 1
                    gains_history(history_frame_counter,:) = max( gains_history(history_frame_counter+1,:)*release_decay_per_block, max(noise_attenuation_factor*ones(1,samples_per_frame),gains_history(history_frame_counter,:)) );
                end

            end

            %Shift history windows:
            ffts_history = circshift(ffts_history,[1,0]);
            spectrums_history = circshift(spectrums_history,[1,0]);
            gains_history = circshift(gains_history,[1,0]);

            %Calculate Enhanced speech frame:
            current_gain_function = gains_history(end,:);
            current_fft = conj(ffts_history(end,:))';
            flag_use_linear_or_log_averaging = 2;
            if number_of_frequency_bins>1
                if flag_use_linear_or_log_averaging==1
                    current_gain_function = conv(current_gain_function,ones(1,number_of_frequency_bins),'same')/number_of_frequency_bins;
                elseif flag_use_linear_or_log_averaging==2
                    current_log_gain_function = log(current_gain_function);
                    current_log_gain_function_averaged = conv(current_gain_function,ones(1,number_of_frequency_bins),'same')/number_of_frequency_bins;
                    current_gain_function_final = exp(current_log_gain_function_averaged);
                end
            else
                current_gain_function_final = current_gain_function;
            end
            fft_after_gain_function = current_fft.*current_gain_function_final' + eps*1i;
            enhanced_frame_current = real(step(IFFT_object,fft_after_gain_function(:)));
              
            %Overlap-Add: 
            first_overlapping_part_of_enhanced_signal = enhanced_frame_current(1:overlap_samples_per_frame) + enhanced_speech_overlapped_samples_from_previous_frame;

            %Remember overlapping part for next overlap-add:
            enhanced_speech_overlapped_samples_from_previous_frame = enhanced_frame_current( samples_per_frame-overlap_samples_per_frame+1 : samples_per_frame);


            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


            %(8). Turn to PM if wanted
            flag_PM_or_FM = 2;
            if flag_PM_or_FM==1;
                filtered_phase = cumsum(filtered_phase);
                filtered_phase = step(signal_filter_object2,filtered_phase(:));
            end

            %Assign final signal:
            final_signal = step(signal_filter_object3,first_overlapping_part_of_enhanced_signal);
            final_signal = cumsum(final_signal)+last_cumsum;
            last_cumsum = final_signal(end);
            

            flag_sound_demodulation=1;
            if flag_sound_demodulation==1
                step(audio_player_object,[final_signal(:),final_signal(:)]);
            end
            
            %Save to .wav file if wanted:
            flag_save_to_wav = 0;
            if flag_save_to_wav==1
                step(audio_file_writer_demodulated,final_signal(:)/3);
            end
            
        end %sub-frame loop
    end %if frame_counter>2 to avoid initial lost samples of system objects
    
    %     %WITHOUT AUDACITY GAIN THIS IS THE WAY TO GET THE FINAL SIGNAL WITH
    %     %REAL TIME AND OVERLAP BETWEEN FRAMES(!!!!):
    %     final_signal = filtered_phase(overlap_samples_per_frame:end);
    
%     step(audio_player_object,filtered_phase);
%     %Sound Demodulation:
%     flag_sound_demodulation = 1;
%     final_signal = cumsum(filtered_phase)+last_filtered_phase;
%     last_filtered_phase = final_signal(end);
%     final_signal = step(signal_filter_object3,final_signal);
%     if flag_sound_demodulation==1 && frame_counter>1
%         step(audio_player_object,[final_signal(:),final_signal(:)]);
%     end
    
    
    
    frame_counter=frame_counter+1;
    toc
end
% profile viewer
% profview

try
    fclose(fid);
    fclose('all');
    release(audio_player_object);
    release(audio_file_writer_demodulated);
    release(audio_file_reader);
    release(analytic_signal_object);
catch 
end














