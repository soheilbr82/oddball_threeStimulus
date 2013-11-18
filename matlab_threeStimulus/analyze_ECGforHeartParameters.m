function heart = analyze_ECGforHeartParameters(ECG, ECG_raw, handles)

    % ECG  - bandpass filtered with "general filter"
    %        [parameters.filter.bandPass_loFreq parameters.filter.bandPass_hiFreq]
    % ECG  - as recorded originally with no manipulations, just trimmed to
    %        match the trigger ON for recording trigger
    
    % handles  - all the settings, parameters, etc.
    
    debugMatFileName = 'tempHeartECG.mat';
    if nargin == 0
        load('debugPath.mat')
        load(fullfile(path.debugMATs, debugMatFileName))
        close all
    else
        if handles.flags.saveDebugMATs == 1
            path = handles.path;
            save('debugPath.mat', 'path')
            save(fullfile(path.debugMATs, debugMatFileName))            
        end
    end  

    scrsz = handles.style.scrsz;
    parameters = handles.parameters;
    style = handles.style;
    
    debugPlotsOn = 0;    
    
    
    
    %% DEBUG PLOT    
    if debugPlotsOn == 1  
        debug_plot(ECG, ECG_raw, parameters, style, handles)     
    end

    %% NOTCH FILTER
    
        % Notch filter for power line interference the ECG_raw (the ECG is also
        % bandpass filtered that distorts the waveform but is passed to this
        % function for educational purposes)        
        heart.vector.ECG_time = (linspace(1,length(ECG_raw),length(ECG_raw))' / parameters.EEG.srate);
        heart.vector.ECG_raw = ECG_raw;
    
        HDR.SampleRate = parameters.EEG.srate;

            disp(['         .. notch filter for raw ECG'])
            ECG_raw = pre_remove5060hz_modified(ECG_raw, HDR, 'PCA 60');  
            heart.vector.ECG_afterNotch = ECG_raw;
    

    %% Modified Pan-Tompkins algorithm implementaion)
    
        % the algorithm fails at 4,096 (too many peaks)        
        x_new = (linspace(1, length(ECG_raw), length(ECG_raw) / parameters.heart.downsampleFactor))';        
        ECG_raw_downsampled = pre_nyquistInterpolation(ECG_raw, length(x_new),1,0); % Nyquist interpolation  
        heartrateSampleRate = parameters.EEG.srate/parameters.heart.downsampleFactor;
        disp(['          .. QRS Detection with Pan-Tompkins'])
        [rPeakTimes, rPeakAmplitudes] = QRS_peakDetection(ECG_raw_downsampled, heartrateSampleRate);
        
        heart.vector.ECG_timeDownSampled = x_new / heartrateSampleRate;
        heart.vector.ECG_rawDownSampled = ECG_raw_downsampled;
        
        recDuration = length(ECG_raw) / parameters.EEG.srate;
        HR = (1 / (recDuration / length(rPeakTimes))) * 60;
        disp(['               - ', num2str(length(rPeakTimes)), ' peaks found from ', num2str(recDuration), ' sec long recording -> HR ~= ', num2str(HR), ', does this make sense?'])
        disp('               - If algorithm fails, and finds too many peaks, the HR fill be insanely high and not physiological anymore!')
        
        if HR > 200
            warning(['Heart rate is over 200! Exactly it is: ', num2str(HR), ' bpm'])
            
            % do something here
        end

            % Add later something more sophisticated for more robust R
            % detection, see for a short review e.g.
                
                % Velic M, Padavic I, Car S. 2013. 
                % Computer aided ECG analysis #x2014; State of the art and upcoming challenges. In: . 2013 IEEE EUROCON p. 1778–1784.
                % http://dx.doi.org/10.1109/EUROCON.2013.6625218            

        %% From ECGTools
        % http://www.robots.ox.ac.uk/~gari/CODE/ECGtools/

            % downsample the ECG to 256 Hz (highest sample rate that the ECGTools
            % implementation runs straight "from the box"
            %{
            downsampleFactor = parameters.EEG.srate / 256;
            try
                ECG_raw_256Hz = downsample(ECG_raw, downsampleFactor)
            catch err
                err % if you have no Signal Processing Toolbox, or someone is using the toolbox
                x_new = (linspace(1, length(ECG_raw), length(ECG_raw) / downsampleFactor))';
                % ECG_raw_256Hz = interp1(ECG_raw, downsampleFactor, 'spline')
                ECG_raw_256Hz = pre_nyquistInterpolation(ECG_raw, length(x_new),1,0);
            end
            Fs = parameters.EEG.srate / downsampleFactor;
            thresh = 0.20;
            [rr, rs] = rrextract(ECG_raw, Fs, thresh)
            [rrPeakInterval, rrPeakAmplitude] = pre_createRRintervalVector(rr, rs, parameters, handles);
            %}

        %% By Grasshopper.iics : http://www.codeproject.com/Articles/309938/ECG-Feature-Extraction-with-Wavelet-Transform-and
            % --> http://www.codeproject.com/Articles/4353/ECG-recording-storing-filtering-and-recognition
    
        
    %% Create R-R interval vector    
    [rrTimes, rrPeakInterval, rrPeakAmplitude] = pre_createRRintervalVector(rPeakTimes, rPeakAmplitudes, parameters, handles);
    
        if debugPlotsOn == 1 
            figure('Color', 'w')
            plot(rrTimes,rrPeakInterval, 'ro', rrTimes, rrPeakAmplitude, 'bo');
            legend('Interval', 'Amplitude', 'Location', 'best'); legend('boxoff')
            xlabel('Time [s]')
        end

    %% Calculate heart rate parameters (Kardia Toolbox)
        
        disp(['           .. Obtain R-R interval time series'])
        [hp, thp] = ecg_hp(rPeakTimes,'instantaneous'); % t is sime as rrTimes            
        
    %% Reject outliers

        [hpOutlierRej, thpOutOutlierRej] = pre_correctHeartRatePeriodForOutliers(rPeakTimes, thp, hp, handles);

        % save to structure
        heart.vector.RR_t = thp;
        heart.vector.RR_timeSeries = hp;      
               
        heart.vector.HR = 60*hp.^-1;

        heart.scalar.HR_Mean = nanmean(heart.vector.HR);
        heart.scalar.HR_Median = nanmedian(heart.vector.HR);        

        plot(hp, thp)

    %% Calculate HRV (Kardia Toolbox)
        disp(['            .. Compute heart Rate Variability (HRV)'])
        [heart, hpFilt] = analyze_HRV_Wrapper(heart, hp, thp, hpOutlierRej, thpOutOutlierRej, rrTimes, rrPeakInterval, rrPeakAmplitude, heartrateSampleRate, parameters, handles);        
        
            % save the heart RR interval data to disk
            disp(['                .. save debug MAT file to disk of both unfiltered and filtered RR timeseries'])
                fileNameOut = sprintf('%s%s', 'RR_timeSeries_', strrep(handles.inputFile, '.bdf', ''), '.mat');
                t = heart.vector.ECG_time;
                Fs = parameters.EEG.srate;
                heartParam = handles.parameters.heart;
                save(fullfile(handles.path.debugHeartOut, fileNameOut), 'hp', 'hpFilt', 'thp', 'heartParam')
            
            disp(['                  .. save debug MAT file to disk of raw ECG'])
                fileNameOut = sprintf('%s%s', 'ECG_', strrep(handles.inputFile, '.bdf', ''), '.mat');
                save(fullfile(handles.path.debugHeartOut, fileNameOut), 't', 'ECG_raw', 'Fs', 'heartParam')

    %% Calculate DFA (Kardia Toolbox)    
        disp(['            .. DFA for R-R timeseries'])
        heart = analyze_heart_DFA_Wrapper(heart, hp, thp, rrTimes, rrPeakInterval, rrPeakAmplitude, heartrateSampleRate, parameters, handles);
        
    
        
    
    function debug_plot(ECG, ECG_raw, parameters, style, handles)
                
        scrsz = handles.style.scrsz;
        fig = figure('Color', 'w');
            set(fig, 'Position', [0.1*scrsz(3) 0.05*scrsz(4) 0.65*scrsz(3) 0.90*scrsz(4)])
            rows = 2;
            cols = 2;
            zoomX = 0.4; % fraction of all x samples
            xDuration = 2.5; % seconds
            t = linspace(1, length(ECG), length(ECG)') / parameters.EEG.srate;
            
        i = 1;
        sp(i) = subplot(rows, cols, i);
            plot(t, ECG); title('Filtered')
        
        i = 2;
        sp(i) = subplot(rows, cols, i);
            plot(t, ECG)
            XStart = t(round(zoomX*length(t)));
            xlim([XStart XStart+xDuration]) 
            
        i = 3;
        sp(i) = subplot(rows, cols, i);
            plot(t, ECG_raw); title('RAW')
            
        i = 4;
        sp(i) = subplot(rows, cols, i);
            plot(t, ECG_raw)
            XStart = t(round(zoomX*length(t)));
            xlim([XStart XStart+xDuration]) 