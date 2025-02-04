function out = cat_vol_groupwise_ls(Nii, output, prec, w_settings, b_settings, s_settings, ord, use_brainmask, reduce, setCOM, isores)
% Groupwise registration via least squares
% FORMAT out = spm_groupwise_ls(Nii, output, prec, w_settings, b_settings, ...
%              s_settings, ord, use_brainmask, reduce, setCOM, isores)
% Nii    - a nifti object for two or more image volumes.
% output - a cell array of output options (as character strings).
%          'wimg   - write realigned images to disk
%          'avg'   - return average in out.avg
%          'wavg'  - write average to disk, and return filename in out.avg
%          'def'   - return mappings from average to individuals in out.def
%          'wdef'  - write mappings to disk, and return filename in out.def
%          'div'   - return divergence of initial velocities in out.div
%          'wdiv'  - write divergence images to disk and return filename
%          'jac'   - return Jacobian determinant maps in out.jac
%          'wjac'  - write Jacobians to disk and return filename
%          'vel'   - return initial velocities
%          'wvel'  - write velocities to disk and return filename
%          'rigid' - return rigid-body transforms
%
% prec       - reciprocal of noise variance on images.
% w_swttings - regularisation settings for warping.
% b_settings - regularisation settings for nonuniformity field.
% s_settings - number of time steps for geodesic shooting.
% ord        - degree of B-spline interpolation used for sampling images.
% use_brainmask - use initial brainmask to obtain better registration
% reduce     - reduce bounding box at final resolution level because usually
%              there is a lot of air around the head after registration of 
%              multiple scans
% setCOM     - set origin using center-of-mass
% isores     - force isotropic average resolution
%              (0-default,1-best,2-worst,3-optimal,<0-defines resolution)
%
%_______________________________________________________________________
% Copyright (C) 2012 Wellcome Trust Centre for Neuroimaging
%
% modified version (added masked registration) of
% John Ashburner
% spm_groupwise_ls.m 6844 2016-07-28 20:02:34Z john $
% ______________________________________________________________________
%
% Christian Gaser, Robert Dahnke
% Structural Brain Mapping Group (https://neuro-jena.github.io)
% Departments of Neurology and Psychiatry
% Jena University Hospital
% ______________________________________________________________________
% $Id cat_vol_groupwise_ls.m $

% Get handles to NIfTI data
%-----------------------------------------------------------------------
if ~isa(Nii,'nifti')
    if isa(Nii,'char')
        Nii = nifti(Nii);
    else
        error('Unrecognised NIfTI images');
    end
end

% Specify default settings
%-----------------------------------------------------------------------
if nargin<3,  prec       = NaN; end
if nargin<4,  w_settings = [0 1 80 20 80]; end
if nargin<5,  b_settings = [0 0 1e6]; end
if nargin<6,  s_settings = 6; end
if nargin<7,  ord        = [3 3 3 0 0 0]; end
if nargin<8,  use_brainmask = 1; end
if nargin<9,  reduce     = 1; end
if nargin<10, setCOM     = 1; end
if nargin<11, isores     = 0; end % force isotropic average resolution (0-default,1-best,2-worst,3-optimal)

% If settings are not subject-specific, then generate
%-----------------------------------------------------------------------
if size(w_settings,1)==1, w_settings = repmat(w_settings,numel(Nii),1); end
if size(s_settings,1)==1, s_settings = repmat(s_settings,numel(Nii),1); end
if size(b_settings,1)==1, b_settings = repmat(b_settings,numel(Nii),1); end
if numel(prec)       ==1, prec       = repmat(prec,1,numel(Nii));       end

% scale all images to a global mean of 100 to ensure consistent weighting of regularisation
for i=1:numel(Nii)
  g = spm_global(spm_vol(Nii(i).dat.fname));
  Nii(i).dat.scl_slope = 100/g*Nii(i).dat.scl_slope;
  Nii(i).dat.scl_inter = 100/g*Nii(i).dat.scl_inter;
end

% correct origin using COM
if setCOM
  for i=1:numel(Nii)
    M0 = spm_imatrix(Nii(i).mat);
    M  = spm_imatrix(cat_vol_set_com(spm_vol(Nii(i).dat.fname))); 
    M0(1:3) = M0(1:3) - M(1:3);
    Nii(i).mat = spm_matrix(M0);
  end
  clear M0 M; 
end

fprintf('\n------------------------------------------------------------------------\n');

% Determine noise estimates when unknown
for i=1:numel(Nii)
  if ~isfinite(prec(i))
    prec0 = spm_noise_estimate(Nii(i));
    fprintf('Estimated noise sd for "%s" = %g\n', Nii(i).dat.fname, prec0);
    if isfinite(prec0)
      prec(i) = prec0.^(-2);
    end
  end
end

% set all values to constant of 1E-3 (empirically estimated) if NaN/Inf values were 
% found in noise estimation
prec(find(~isfinite(prec))) = 1E-3;

% Basis functions for algebra of rigid-body transform
%-----------------------------------------------------------------------
B = se3_basis;

% Set boundary conditions 
%-----------------------------------------------------------------------
spm_field('boundary',1); % Bias correction - Neumann
spm_diffeo('boundary',0);     % Diffeomorphism  - circulant

% Computations for figuring out how many grid levels are likely to work
%-----------------------------------------------------------------------
d = [0 0 0];
for i=1:numel(Nii)
    dm = [size(Nii(i).dat) 1];
    d  = max(d, dm(1:3));
end
if isores
  d = max(d);
elseif isores<0
  d = -isores;
else
  d = min(d);
end

% Specify highest resolution data
%-----------------------------------------------------------------------
clear pyramid
pyramid(max(ceil(log2(d)-log2(4)),1)) = struct('d',[1 1 1],'mat',eye(4),'img',[]);
for i=numel(Nii):-1:1
    pyramid(1).img(i).f   = single(Nii(i).dat(:,:,:,1,1));
    pyramid(1).img(i).mat = Nii(i).mat;
end

% Generate sucessively lower resolution versions
%-----------------------------------------------------------------------
for level = 2:numel(pyramid)
    for i=numel(Nii):-1:1
        pyramid(level).img(i).f   = spm_diffeo('restrict',pyramid(level-1).img(i).f);
        pyramid(level).img(i).f(~isfinite(pyramid(level).img(i).f)) = 0;
        s1 = [size(pyramid(level-1).img(i).f) 1];
        s2 = [size(pyramid(level  ).img(i).f) 1];
        s  = s1(1:3)./s2(1:3);
        pyramid(level).img(i).mat = pyramid(level-1).img(i).mat*[diag(s), (1-s(:))*0.5; 0 0 0 1];
        clear s1 s2
    end
end

% Convert all image data into B-spline coefficients (for interpolation)
%-----------------------------------------------------------------------
for level=1:numel(pyramid)
    for i=1:numel(Nii)
        pyramid(level).img(i).f = spm_diffeo('bsplinc',pyramid(level).img(i).f,ord);
    end
end

% Adjust precision for number of subjects
%-----------------------------------------------------------------------
%nscan = numel(pyramid(1).img);
%prec  = prec*(nscan-1)/nscan;

% Stuff for figuring out the orientation, dimensions etc of the highest resolution template
%-----------------------------------------------------------------------
Mat0 = cat(3,pyramid(1).img.mat);
if isores ~= 0   
  %% RD20220217: use best resolution and create an isotropic output 
  mati      = spm_imatrix(Mat0); 
  vx_vol    = mati(7:9); 
  switch isores 
    case 1
      vx_vol = min(vx_vol); 
    case 2 % need at least something like 2 mm
      vx_vol = min(2,max(vx_vol));
    case 3 
      % optimal - keep the volume similar but move it a bit torwards one
      %   eg. 1.0x1.0x3.0 > 1.2, 0.5x0.5x1.0 > 0.7
      vx_vol  = floor( (prod(abs(vx_vol)).^(1/3) ).^0.5  * 10 ) / 10;
    case 4 % similar volume and between 1 and 2 mm
      vx_vol  = min(2,max(1,min(vx_vol)));
    case 5 % get higher resolution
      vx_vol  = floor( (prod(abs(vx_vol)).^(1/3) ).^0.5  * 10 ) / 10;
    otherwise
      vx_vol  = repmat(-isores,1,3);
  end
  cdim      = mati(7:9) ./ vx_vol; 
  mati(7:9) = vx_vol; 
  Mat0      = spm_matrix(mati); 
else
  cdim      = [1 1 1];
end
dims = zeros(numel(Nii),3);
for i=1:size(dims,1)
    dims(i,:) = round(Nii(i).dat.dim(1:3) .* cdim);
end
[pyramid(1).mat,pyramid(1).d] = compute_avg_mat(Mat0,dims);
pyramid(1).sc   = abs(det(pyramid(1).mat(1:3,1:3)));
pyramid(1).prec = prec;

% Figure out template info for each sucessively lower resolution version
%-----------------------------------------------------------------------
for level=2:numel(pyramid)
    pyramid(level).d    = ceil(pyramid(level-1).d/2);
    s                   = pyramid(level-1).d./pyramid(level).d;
    pyramid(level).mat  = pyramid(level-1).mat*[diag(s), (1-s(:))*0.5; 0 0 0 1];

    % Relative scaling of regularisation
    pyramid(level).sc   = abs(det(pyramid(level).mat(1:3,1:3)));
    pyramid(level).prec = prec*sqrt(pyramid(level).sc/pyramid(1).sc); % Note that the sqrt is ad hoc
end


nlevels = numel(pyramid);
brainmask = [];

% check whether reduce option is enabled for non-linear registration
if all(isfinite(w_settings(:))) & reduce
  reduce = 0;
  use_brainmask = 0; 
  fprintf('Reducing bounding box is not supported for non-linear registration and will be disabled.\n');
end

for level=nlevels:-1:1 % Loop over resolutions, starting with the lowest

    % Collect data
    %-----------------------------------------------------------------------
    img       = pyramid(level).img;
    M_avg     = pyramid(level).mat;
    d         = pyramid(level).d;
    vx        = sqrt(sum(pyramid(level).mat(1:3,1:3).^2));
    sc        = pyramid(level).sc;
    prec      = pyramid(level).prec;

    if level==nlevels
        % If lowest resolution, initialise parameter estimates to zero
        %-----------------------------------------------------------------------
        clear param
        bias_est = zeros(numel(Nii),1);
        for i=numel(Nii):-1:1
            bias_est(i) = log(mean(mean(mean(img(i).f))));
        end
        bias_est = bias_est - mean(bias_est);
        for i=numel(Nii):-1:1
            param(i) = struct('R',   eye(4), 'r', zeros(6,1),...
                              'bias',[],     'eb',0,...
                              'v0',  [],     'ev',0, 'y',[], 'J',[],...
                              's2',  1,      'ss',1);

            if all(isfinite(b_settings(i,:)))
                param(i).bias = zeros(size(img(i).f),'single')+bias_est(i);
            end

            if all(isfinite(w_settings(i,:)))
                param(i).v0   = zeros([d 3],'single');
                param(i).y    = identity(d);
                param(i).J    = repmat(reshape(eye(3,'single'),[1 1 1 3 3]),[d(1:3),1,1]);
            end

        end
    else
        % Initialise parameter estimates by prolongation of previous lower resolution versions.
        %-----------------------------------------------------------------------
        for i=1:numel(Nii)

            if all(isfinite(b_settings(i,:)))
                vxi           = sqrt(sum(img(i).mat(1:3,1:3).^2));
                spm_diffeo('boundary',1);
                param(i).bias = spm_diffeo('resize',param(i).bias,size(img(i).f));
                spm_diffeo('boundary',0);
                bmom          = spm_field('vel2mom', param(i).bias, [vxi b_settings(i,:)*sc]);
                param(i).eb   = sum(bmom(:).*param(i).bias(:));
                clear bmom
            else
                param(i).bias = [];
                param(i).eb   = 0;
            end

            if all(isfinite(w_settings(i,:)))
                param(i).v0   = spm_diffeo('resize',param(i).v0,d);
                for i1=1:3
                    s = pyramid(level).d(i1)/pyramid(level+1).d(i1);
                    param(i).v0(:,:,:,i1) = param(i).v0(:,:,:,i1)*s;
                end
                m0          = spm_diffeo('vel2mom',param(i).v0,[vx w_settings(i,:)*sc]);
                param(i).ev = sum(sum(sum(sum(m0.*param(i).v0))));
                clear m0
            else
                param(i).v0 = [];
                param(i).ev = 0;
                param(i).y  = [];
                param(i).J  = [];
            end
        end

        % Remove lower resolution versions that are no longer needed
        pyramid = pyramid(1:(end-1));
    end

    spm_plot_convergence('Clear');
    spm_plot_convergence('Init',['Optimising (level ' num2str(level) ')'],'Objective Function','Step');
    for iter=1:(2*2^(level-1)+1) % / 8 % Use more iterations at lower resolutions (its faster, so may as well) ############# RD20220213 marked
      % RD20220213: markings for future experiments
      %  I marked some parts of using bias correction and deformations, 
      %  because they are interesting in case case of development, adaptions 
      %  of the scanner protocol or device itself.
      %  Soft, very low frequency changes could be interesting. However, 
      %  the necessary adaptions of the long pipeline are curenty to much 
      %  for this quite rare case that would remain still complicated.
      %  Changes would need extra flag for the protocol case. 
      %  The developmental changes would require separate processing of the
      %  average (with deformation) and of the single time-points (without
      %  deformations) to get correct measurements.


        % Compute deformations from initial velocities
        %-----------------------------------------------------------------------
        
        for i=1:numel(param)
            if all(isfinite(w_settings(i,:)))
                [param(i).y,param(i).J] = spm_shoot3d(param(i).v0,[vx w_settings(i,:)*sc],s_settings(i,:));
            end
        end

        if true
            % Rigid-body
            %=======================================================================
            % Recompute template data (with gradients)
            %-----------------------------------------------------------------------
            [mu,ss,nvox,D] = compute_mean(pyramid(level), param, ord);
            % for i=1:numel(param), fprintf('  %12.5g %12.5g %12.5g', prec(i)*ss(i), param(i).eb, param(i).ev); end; fprintf('  0\n');

            if (level == 1) && (iter == 1)
              vx_vol  = sqrt(sum(pyramid(level).mat(1:3,1:3).^2)); 
              
              % reduce bounding box at final resolution level
              if reduce
                fprintf('Reduce bounding box for final resolution level.\n');
                
                % intensity normalization using 99% of data (to ignore outliers)
                [msk,hth] = cat_stat_histth(smooth3(mu),0.99,0); 
                msk = (msk - hth(1)) ./ abs(diff(hth));
                
                % masking (borrowed from head-trimming)
                msk = smooth3(msk)>0.05; 
                msk = cat_vol_morph(msk,'do',2,vx_vol); 
                msk = cat_vol_morph(msk,'l',[10 0.1]); 
                [msk,redB] = cat_vol_resize(mu,'reduceBrain',vx_vol,2,msk); 
                clear msk
            
                % correct mat information and dimensions
                mati  = spm_imatrix(pyramid(level).mat); matio = mati; 
                mati(1:3) = mati(1:3) + mati(7:9).*(redB.BB(1:2:end) - 1);
                pyramid(level).mat = spm_matrix(mati);
                pyramid(level).d = redB.sizeTr;
                
                % update some size-dependent parameters
                M_avg     = pyramid(level).mat;
                d         = pyramid(level).d;
  
                % re-estimate mu using new dimensions
                [mu,ss,nvox,D] = compute_mean(pyramid(level), param, ord);
              end          

              % create mask at final level to allow masked registration
              if use_brainmask
                fprintf('Use initial brainmask for final resolution level.\n');
                
                PG = cat_get_defaults('extopts.T1');
                PB = cat_get_defaults('extopts.brainmask');

                [pth,nam]   = fileparts(Nii(1).dat.fname);
                nam         = fullfile(pth,['avg_' nam '.nii']);
                Nio         = nifti;
                Nio.dat     = file_array(nam,size(mu),'float32',0,1,0);
                Nio.mat     = M_avg;
                Nio.mat0    = Nio.mat;
                Nio.mat_intent  = 'Aligned';
                Nio.mat0_intent = Nio.mat_intent;
                Nio.descrip = sprintf('Average of %d', numel(param));
                create(Nio);
                Nio.dat(:,:,:) = mu;
                PF = nam;

                try
                  [Ym, brainmask] = cat_long_APP(PF,PG,PB);
                  brainmask(~isfinite(brainmask)) = 0;
                catch
                  fprintf('Creation of brainmask failed. No brainmask will be used for final registration.\n');
                  use_brainmask = 0;
                end

                % re-estimate mu using new dimensions
                if use_brainmask
                  [brainmask,redB] = cat_vol_resize(brainmask,'reduceBrain',vx_vol, 25 ,brainmask>0.5); % area around brainmask should cover full head 20-30 mm
                  clear msk
                   
                  % correct mat information and dimensions
                  mati  = spm_imatrix(pyramid(level).mat); matio = mati; 
                  mati(1:3) = mati(1:3) + mati(7:9).*(redB.BB(1:2:end) - 1);
                  pyramid(level).mat = spm_matrix(mati);
                  pyramid(level).d = redB.sizeTr;

                  % update some size-dependent parameters
                  M_avg     = pyramid(level).mat;
                  d         = pyramid(level).d;
  
                  [mu,ss,nvox,D] = compute_mean(pyramid(level), param, ord);
                end
                
                clear Ym
                spm_plot_convergence('Clear');
                spm_plot_convergence('Init',['Optimising (level ' num2str(level) ') with brainmask'],'Objective Function','Step');
              end
            end

            % Compute objective function (approximately)
            %-----------------------------------------------------------------------
            ll = 0;
            for i=1:numel(param)
                param(i).ss = ss(i);
                ll          = ll - 0.5*prec(i)*param(i).ss - 0.5*param(i).eb - 0.5*param(i).ev;
            end
            spm_plot_convergence('set',ll);

            for i=1:numel(img)
                % Gauss-Newton update of logs of rigid-body matrices
                %-----------------------------------------------------------------------
                [R,dR]        = spm_dexpm(param(i).r,B);
                M             = img(i).mat\R*M_avg;
                dtM           = abs(det(M(1:3,1:3)));
                [x1a,x2a,x3a] = ndgrid(1:d(1),1:d(2),1);

                Hess = zeros(12);
                gra  = zeros(12,1);
                for m=1:d(3)
                    if all(isfinite(w_settings(i,:)))
                        dt    = spm_diffeo('det',param(i).J(:,:,m,:,:));
                        y     = transform_warp(M,param(i).y(:,:,m,:));
                    else
                        dt    = ones(d(1:2),'single');
                        y     = zeros([d(1:2) 1 3],'single');
                        [y(:,:,1),y(:,:,2),y(:,:,3)] = ndgrid(single(1:d(1)),single(1:d(2)),single(m));
                        y     = transform_warp(M,y);
                    end

                    f     = spm_diffeo('bsplins',img(i).f,y,ord);

                    if all(isfinite(b_settings(i,:)))
                        ebias = exp(spm_diffeo('pullc',param(i).bias,y));
                    else
                        ebias = ones(size(f),'single');
                    end

                    b     = f-mu(:,:,m).*ebias;

                    msk  = isfinite(b);
                    % use different mask for rigid body registration if brainmask is defined
                    if (level == 1) && use_brainmask && ~isempty(brainmask)
                      mskr = isfinite(b) & (brainmask(:,:,m) > 0.25);
                    else
                      mskr = isfinite(b);
                    end

                    if ~all(isfinite(w_settings(i,:)))
                      ebias = ebias(mskr);
                      b     = b(mskr);
                    else
                      ebias = ebias(msk);
                      b     = b(msk);
                    end

                    if ~all(isfinite(w_settings(i,:)))
                        % No need to account for the nonlinear warps when estimating
                        % the rigid body transform.
                        x1 = x1a(mskr);
                        x2 = x2a(mskr);
                        x3 = x3a(mskr)*m;
                        d1 = D{1}(:,:,m);
                        d2 = D{2}(:,:,m);
                        d3 = D{3}(:,:,m);

                    else
                        % The rigid-body transform should register the nonlinearly warped
                        % template to match the individual.


                        % Positions where the template voxels are mapped to via the nonlinear warp.
                        x1 = param(i).y(:,:,m,1); x1 = x1(msk);
                        x2 = param(i).y(:,:,m,2); x2 = x2(msk);
                        x3 = param(i).y(:,:,m,3); x3 = x3(msk);


                        % Gradients of nonlinear warped template, warped back to its original space.
                        % Multiply by transpose of inverse of Jacobian determinants.
                        % First, get the Jacobians of the nonlinear warp.
                        J           = reshape(param(i).J(:,:,m,:,:),[d(1:2) 3 3]);

                        % Reciprocal of the determinants.  Note that for the gradients (gra)
                        % idt cancels out with dt. For the Hessians (Hess), it doesn't.
                        idt         = 1./max(dt,0.001);

                        % Compute cofactors of Jacobians, where cJ = det(J)*inv(J) 
                        cJ          = zeros(size(J),'single');
                        cJ(:,:,1,1) = J(:,:,2,2).*J(:,:,3,3) - J(:,:,2,3).*J(:,:,3,2);
                        cJ(:,:,1,2) = J(:,:,1,3).*J(:,:,3,2) - J(:,:,1,2).*J(:,:,3,3);
                        cJ(:,:,1,3) = J(:,:,1,2).*J(:,:,2,3) - J(:,:,1,3).*J(:,:,2,2);

                        cJ(:,:,2,1) = J(:,:,2,3).*J(:,:,3,1) - J(:,:,2,1).*J(:,:,3,3);
                        cJ(:,:,2,2) = J(:,:,1,1).*J(:,:,3,3) - J(:,:,1,3).*J(:,:,3,1);
                        cJ(:,:,2,3) = J(:,:,1,3).*J(:,:,2,1) - J(:,:,1,1).*J(:,:,2,3);

                        cJ(:,:,3,1) = J(:,:,2,1).*J(:,:,3,2) - J(:,:,2,2).*J(:,:,3,1);
                        cJ(:,:,3,2) = J(:,:,1,2).*J(:,:,3,1) - J(:,:,1,1).*J(:,:,3,2);
                        cJ(:,:,3,3) = J(:,:,1,1).*J(:,:,2,2) - J(:,:,1,2).*J(:,:,2,1);

                        % Premultiply gradients by transpose of inverse of J
                        d1 = idt.*(cJ(:,:,1,1).*D{1}(:,:,m) + cJ(:,:,2,1).*D{2}(:,:,m) + cJ(:,:,3,1).*D{3}(:,:,m));
                        d2 = idt.*(cJ(:,:,1,2).*D{1}(:,:,m) + cJ(:,:,2,2).*D{2}(:,:,m) + cJ(:,:,3,2).*D{3}(:,:,m));
                        d3 = idt.*(cJ(:,:,1,3).*D{1}(:,:,m) + cJ(:,:,2,3).*D{2}(:,:,m) + cJ(:,:,3,3).*D{3}(:,:,m));

                        clear idt cJ
                    end

                    if ~all(isfinite(w_settings(i,:)))
                      dt = dt(mskr);
                      d1 = d1(mskr).*ebias;
                      d2 = d2(mskr).*ebias;
                      d3 = d3(mskr).*ebias;
                    else
                      dt = dt(msk);
                      d1 = d1(msk).*ebias;
                      d2 = d2(msk).*ebias;
                      d3 = d3(msk).*ebias;
                    end
                    
                    % Derivatives w.r.t. an affine transform
                    A     = [x1(:).*d1(:) x1(:).*d2(:) x1(:).*d3(:) ...
                             x2(:).*d1(:) x2(:).*d2(:) x2(:).*d3(:) ...
                             x3(:).*d1(:) x3(:).*d2(:) x3(:).*d3(:) ...
                                    d1(:)        d2(:)        d3(:)];

                    if ~all(isfinite(w_settings(i,:)))
                        Hess  = Hess + dtM*double(A'*A);
                        gra   = gra  + dtM*double(A'*b);
                    else
                        Hess  = Hess + dtM*double(A'*bsxfun(@times,A,dt));
                        gra   = gra  + dtM*double(A'*(dt.*b));
                    end

                    clear dt y f ebias b msk x1 x2 d1 d2 d3 A 
                end

                % For converting from derivatives w.r.t. an affine transform
                % to derivatives w.r.t. the rigid-body transform parameters.
                dA = zeros(12,6);
                for m=1:6
                    tmp     = (R*M_avg)\dR(:,:,m)*M_avg;
                    dA(:,m) = reshape(tmp(1:3,:),12,1);
                end

                Hess       = dA'*Hess*dA*prec(i);
                gra        = dA'*gra*prec(i);
                
                % only use Hessian and gra if finite
                if all(isfinite(Hess(:))) & all(isfinite(gra(:)))
                  param(i).r = param(i).r - Hess\gra;
                else
                  fprintf('Warning: Hessian matrix could not be estimated for %s\n',Nii(i).dat.fname);
                end

                clear R dR M x1a x2a dA tmp Hess gra
            end
            clear mu D

            % Mean correct the rigid-body transforms and compute exponentials
            % Note that this gives us a Karcher mean.
            %-----------------------------------------------------------------------
            r_avg = mean(cat(2,param.r),2);
            for i=1:numel(param)
                param(i).r = param(i).r-r_avg;
                param(i).R = spm_dexpm(param(i).r,B);
            end
            clear r_avg
        end
        
        if any(all(isfinite(b_settings),2)) %&& level>4 %######## RD20220213 marked  
            % Bias field
            %fprintf('Bias %d-%d\n',level,iter); % ######## RD20220213 marked
            %=======================================================================
            % Recompute template data
            %-----------------------------------------------------------------------
            [mu,ss] = compute_mean(pyramid(level), param, ord);
            % for i=1:numel(param), fprintf('  %12.5g %12.5g %12.5g', prec(i)*ss(i), param(i).eb, param(i).ev); end; fprintf('  1\n');

            % Compute objective function (approximately)
            %-----------------------------------------------------------------------
            ll = 0;
            for i=1:numel(param)
                param(i).ss = ss(i);
                ll          = ll - 0.5*prec(i)*param(i).ss - 0.5*param(i).eb - 0.5*param(i).ev;
            end
            spm_plot_convergence('set',ll);

            for i=1:numel(img)
                if all(isfinite(b_settings(i,:)))
                    % Gauss-Newton update of logs of bias field.
                    % Note that 1st and second derivatives are computed in template space
                    % and subsequently pushed back to native space for re-estimation.
                    %-----------------------------------------------------------------------
                    M    = img(i).mat\param(i).R*M_avg;
                    gra  = zeros(d,'single');
                    Hess = zeros(d,'single');

                    for m=1:d(3)
                        if all(isfinite(w_settings(i,:)))
                            dt    = spm_diffeo('det',param(i).J(:,:,m,:,:))*abs(det(M(1:3,1:3)));
                            y     = transform_warp(M,param(i).y(:,:,m,:));
                        else
                            dt    = ones(d(1:2),'single')*abs(det(M(1:3,1:3)));
                            y     = zeros([d(1:2) 1 3],'single');
                            [y(:,:,1),y(:,:,2),y(:,:,3)] = ndgrid(single(1:d(1)),single(1:d(2)),m);
                            y     = transform_warp(M,y);
                        end

                        f           = spm_diffeo('bsplins',img(i).f,y,ord);
                        ebias       = exp(spm_diffeo('pullc',param(i).bias,y));

                        msk         = isfinite(f) & isfinite(ebias);
                        smu         = mu(:,:,m).*ebias;
                        f(~msk)     = 0;
                        smu(~msk)   = 0;
                        gra(:,:,m)  = smu.*(smu-f).*dt*prec(i);
                        Hess(:,:,m) = smu.*smu.*dt*prec(i);

                        clear dt y f ebias msk smu
                    end

                    % Push derivatives to native space
                    %-----------------------------------------------------------------------
                    if all(isfinite(w_settings(i,:)))
                        y    = transform_warp(M,param(i).y);
                    else
                        y    = transform_warp(M,identity(d));
                    end
                    gra  = spm_diffeo('push',gra,y,size(param(i).bias));
                    Hess = spm_diffeo('push',Hess,y,size(param(i).bias));
                    clear y

                    vxi           = sqrt(sum(img(i).mat(1:3,1:3).^2));
                    gra           = gra + spm_field('vel2mom', param(i).bias, [vxi b_settings(i,:)*sc]);
                    param(i).bias = param(i).bias - spm_field(Hess,gra,[vxi b_settings(i,:)*sc 2 2]); % Gauss-Newton update
                    clear M gra Hess

                    % Compute part of objective function
                    %-----------------------------------------------------------------------
                    bmom          = spm_field('vel2mom', param(i).bias, [vxi b_settings(i,:)*sc]);
                    param(i).eb   = sum(bmom(:).*param(i).bias(:));
                    clear bmom vxi
                end
            end
            clear mu
        end

        if any(all(isfinite(w_settings),2)) %&& level>4 % ########## RD20220213 marked
            % Deformations
            %=======================================================================
            % Recompute template data (with gradients)
            %-----------------------------------------------------------------------
            %fprintf('Defs %d-%d\n',level,iter); %##########   RD20220213 marked 
            [mu,ss,nvox,D] = compute_mean(pyramid(level), param, ord);
            % for i=1:numel(param), fprintf('  %12.5g %12.5g %12.5g', prec(i)*ss(i), param(i).eb, param(i).ev); end; fprintf('  2\n');

            % Compute objective function (approximately)
            %-----------------------------------------------------------------------
            ll = 0;
            for i=1:numel(param)
                param(i).ss = ss(i);
                ll          = ll - 0.5*prec(i)*param(i).ss - 0.5*param(i).eb - 0.5*param(i).ev;
            end
            spm_plot_convergence('set',ll);

            for i=1:numel(img) % Update velocity for each image in turn
                if all(isfinite(w_settings(i,:)))
                    % Gauss-Newton update of velocity fields.
                    % These are parameterised in template space.
                    %-----------------------------------------------------------------------
                    gra  = zeros([d,3],'single');
                    Hess = zeros([d,6],'single');
                    M    = img(i).mat\param(i).R*M_avg;

                    for m=1:d(3)
                        dt    = spm_diffeo('det',param(i).J(:,:,m,:,:))*abs(det(M(1:3,1:3)));
                        y     = transform_warp(M,param(i).y(:,:,m,:));
                        f     = spm_diffeo('bsplins',img(i).f,y,ord);

                        if all(isfinite(b_settings(i,:)))
                            ebias = exp(spm_diffeo('pullc',param(i).bias,y));
                        else
                            ebias = ones(size(f),'single');
                        end

                        b             = f-mu(:,:,m).*ebias;
                        msk           = ~isfinite(b);
                        b(msk)        = 0;
                        dt(msk)       = 0;

                        d1            = D{1}(:,:,m).*ebias; % Spatial gradient of -b.
                        d2            = D{2}(:,:,m).*ebias;
                        d3            = D{3}(:,:,m).*ebias;

                        gra(:,:,m,1)  =  b.*d1.*dt; % 1st derivatives of objecive function
                        gra(:,:,m,2)  =  b.*d2.*dt; % w.r.t. velocity field.
                        gra(:,:,m,3)  =  b.*d3.*dt;

                        Hess(:,:,m,1) = d1.*d1.*dt; % 2nd derivatives (approximately) of
                        Hess(:,:,m,2) = d2.*d2.*dt; % objective function w.r.t. velocity.
                        Hess(:,:,m,3) = d3.*d3.*dt;
                        Hess(:,:,m,4) = d1.*d2.*dt;
                        Hess(:,:,m,5) = d1.*d3.*dt;
                        Hess(:,:,m,6) = d2.*d3.*dt;

                        clear dt y f ebias b msk d1 d2 d3
                    end

                    param(i).y = []; % No longer needed, so free up some memory.
                    param(i).J = [];

                    Hess        = Hess*prec(i);
                    gra         = gra*prec(i);

                    gra         = gra + spm_diffeo('vel2mom',param(i).v0,[vx w_settings(i,:)*sc]);
                    param(i).v0 = param(i).v0 - spm_diffeo('fmg',Hess, gra, [vx w_settings(i,:)*sc 2 2]); % Gauss-Newton

                    clear Hess gra
                end
            end
            clear mu D

            % If regularisation is the same for each image (apart from scaling), then adjust velocities.
            %-----------------------------------------------------------------------
            if sum(var(diag(sqrt(sum(w_settings.^2,2)))\w_settings,0,1)./(mean(w_settings,1).^2+eps)) < 1e-12
                wt      = sqrt(sum(w_settings.^2,2));
                wt      = wt/sum(wt);
                v0_mean = zeros(size(param(1).v0),'single');
                for i=1:numel(param)
                    v0_mean = v0_mean + wt(i)*param(i).v0;
                end
                for i=1:numel(param)
                    param(i).v0 = param(i).v0 - v0_mean;
                end
                clear v0_mean
            end

            % Compute part of objective function
            %-----------------------------------------------------------------------
            for i=1:numel(param)
                if all(isfinite(w_settings(i,:)))
                    m0          = spm_diffeo('vel2mom',param(i).v0,[vx w_settings(i,:)*sc]);
                    param(i).ev = sum(sum(sum(sum(m0.*param(i).v0))));
                    clear m0
                end
            end

        end
    end
end

% Figure out what needs to be saved
%-----------------------------------------------------------------------
need_avg = false;
need_vel = false;
need_def = false;
need_div = false;
need_jac = false;
need_mom = false;
need_bia = false;
need_wimg= false;

if any(strcmp('avg',output)) || any(strcmp('wavg',output)), need_avg = true; end
if any(strcmp('vel',output)) || any(strcmp('wvel',output)), need_vel = true; end
if any(strcmp('div',output)) || any(strcmp('wdiv',output)), need_div = true; end
if any(strcmp('def',output)) || any(strcmp('wdef',output)), need_def = true; end
if any(strcmp('jac',output)) || any(strcmp('wjac',output)), need_jac = true; end
if any(strcmp('mom',output)) || any(strcmp('wmom',output)), need_mom = true; end
if any(strcmp('bia',output)) || any(strcmp('wbia',output)), need_bia = true; end
if any(strcmp('wimg',output)),                              need_wimg= true; end

out = struct;
if need_avg || need_def || need_jac
    for i=numel(param):-1:1
        if all(isfinite(w_settings(i,:)))
            [param(i).y,param(i).J] = spm_shoot3d(param(i).v0,[vx w_settings(i,:)*sc],s_settings(i,:));
        end
    end
end

clear out
out.mat = M_avg;

if any(strcmp('rigid',output))
    out.rigid = {};
    for i=1:numel(param)
        out.rigid{i} = param(i).R;
    end
end

mu  = compute_mean(pyramid(1), param, ord);
vol = get_transformed_images(pyramid(1), param, ord);

% do some final bias correction between scans which is more effective and also masked
bias_nits = 8;
bias_fwhm = 60;
bias_reg = 1e-6;
bias_lmreg = 1e-6;
for i=1:numel(param)
  tmp_vol = vol(:,:,:,i);
  ind0 = tmp_vol == 0;
    
  [tmp_vol th99] = cat_stat_histth(tmp_vol,[0.99 0.999]);
  tmp_vol = tmp_vol - th99(1);

  % if > 0.5% of values are zero then set these areas back to zero
  if 100*sum(ind0(:))/numel(tmp_vol) > 0.5
    tmp_vol(ind0) = 0;
  end
  vol(:,:,:,i) = tmp_vol;
  vol(:,:,:,i) = bias_correction(mu,vol(:,:,:,i),[],pyramid(1),bias_nits,bias_fwhm,bias_reg,bias_lmreg);
end

% correct if minimum is < 0
min_vol = min(vol(:));
if min_vol < 0
  for i=1:numel(param)
    tmp_vol = vol(:,:,:,i);
    ind0 = tmp_vol == 0;
    
    tmp_vol = tmp_vol - min_vol;
    
    % if > 0.5% of values are zero then set these areas back to zero
    if 100*sum(ind0(:))/numel(tmp_vol) > 0.5
      tmp_vol(ind0) = 0;
    end

    vol(:,:,:,i) = tmp_vol;
    
  end
else
  if min_vol < 0, vol = vol - min_vol; end
end

if need_wimg
    for i=1:numel(param)
        img = vol(:,:,:,i);
        [pth,nam]   = fileparts(Nii(i).dat.fname);
        nam         = fullfile(pth,['r' nam '.nii']);
        Nio         = nifti;
        Nio.dat     = file_array(nam,size(img),'float32',0,1,0);
        Nio.mat     = M_avg;
        Nio.mat0    = Nio.mat;
        Nio.mat_intent  = 'Aligned';
        Nio.mat0_intent = Nio.mat_intent;
        Nio.descrip = sprintf('Realigned %d', numel(param));
        create(Nio);
        Nio.dat(:,:,:) = img;
        out.rimg{i}    = nam;
    end
end

if need_avg
    %% use weighted median/mean for rigid registration and mean for non-linear registration
    if all(isfinite(w_settings(i,:))) % rigid registration
        vol_mean   = mean(vol,4);
        % use median for > 2 images, otherwise use min
        if numel(param) > 2
            vol_median = median(vol,4);
        else
            vol_median = min(vol,[],4);
        end
        vol_std    = std(vol,[],4);
        
        % get 0..95% range
        [nvol,hvol] = hist(vol_std(:),100);
        nvol = nvol./numel(vol_std(:));
        quantile95 = hvol(find(cumsum(nvol)/sum(nvol)>0.95,1,'first')); 
        
        % scale std image with quantile95 value and limit range 0..1
        vol_std = vol_std./quantile95;
        vol_std(vol_std>1) = 1;
        
        % weighted scaling w.r.t. local std
        mu = vol_std.*vol_median + (1-vol_std).*vol_mean;

    else % non-linear registration
        mu = mean(vol,4);
    end
    
    if any(strcmp('wavg',output))
        [pth,nam]   = fileparts(Nii(1).dat.fname);
        nam         = fullfile(pth,['avg_' nam '.nii']);
        Nio         = nifti;
        Nio.dat     = file_array(nam,size(mu),'float32',0,1,0);
        Nio.mat     = M_avg;
        Nio.mat0    = Nio.mat;
        Nio.mat_intent  = 'Aligned';
        Nio.mat0_intent = Nio.mat_intent;
        Nio.descrip = sprintf('Median of %d', numel(param));
        create(Nio);
        Nio.dat(:,:,:) = mu;
        out.avg       = {nam};
    else
        out.avg       = mu;
    end
end

if need_mom
    out.mom = {};
    for i=1:numel(param)
        if all(isfinite(w_settings(i,:)))

            mom = zeros(d,'single');
            M   = img(i).mat\param(i).R*M_avg;

            for m=1:d(3)
                dt    = spm_diffeo('det',param(i).J(:,:,m,:,:));
                y     = transform_warp(M,param(i).y(:,:,m,:));
                f     = spm_diffeo('bsplins',img(i).f,y,ord);
                ebias = exp(spm_diffeo('pullc',param(i).bias,y));
                b     = (f-mu(:,:,m).*ebias).*ebias.*dt;
                b(~isfinite(b)) = 0;
                mom(:,:,m) = b;
                clear dt y f ebias b msk 
            end

            if any(strcmp('wmom',output))
                [pth,nam]   = fileparts(Nii(i).dat.fname);
                nam         = fullfile(pth,['a_' nam '.nii']);
                Nio         = nifti;
                Nio.dat     = file_array(nam,d,'float32',0,1,0);
                Nio.mat     = M_avg;
                Nio.mat0    = Nio.mat;
                Nio.mat_intent  = 'Aligned';
                Nio.mat0_intent = Nio.mat_intent;

                Nio.descrip = sprintf('Scalar Mom (%.3g %.3g %.3g %.3g %.3g) (%d)',w_settings(i,:)*sc,s_settings(i,1));
                create(Nio);
                Nio.dat(:,:,:,1,1) = mom;
                out.mom{i}         = nam;
            else
                out.mom{i}         = mom;
            end
            clear mom
        end
    end
end

clear mu;

if need_bia
    out.bia = {};
    for i=1:numel(param)
        if all(isfinite(b_settings(i,:)))

            if any(strcmp('wbia',output))
                [pth,nam]   = fileparts(Nii(i).dat.fname);
                nam         = fullfile(pth,['BiasField_' nam '.nii']);
                Nio         = nifti;
                dm          = [Nii(i).dat.dim 1]; dm = dm(1:3);
                Nio.dat     = file_array(nam,dm,'float32',0,1,0);
                Nio.mat     = Nii(i).mat;
                Nio.mat0    = Nii(i).mat0;
                Nio.mat_intent  = Nii(i).mat_intent;
                Nio.mat0_intent = Nii(i).mat0_intent;

                Nio.descrip     = 'Bias Field';
                create(Nio);
                Nio.dat(:,:,:)  = exp(param(i).bias);
                out.bia{i}      = nam;
            else
                out.bia{i}      = exp(param(i).bias);
            end
            clear mom
        end
    end
end

if need_def
    out.def = {};
    for i=numel(param):-1:1
        if all(isfinite(w_settings(i,:)))

            M   = param(i).R*M_avg;
            for m=1:d(3)
                param(i).y(:,:,m,:) = transform_warp(M,param(i).y(:,:,m,:));
            end
            if any(strcmp('wdef',output))
                [pth,nam]   = fileparts(Nii(i).dat.fname);
                nam         = fullfile(pth,['y_' nam '.nii']);
                Nio         = nifti;
                Nio.dat     = file_array(nam,[d 1 3],'float32',0,1,0);
                Nio.mat     = M_avg;
                Nio.mat0    = Nio.mat;
                Nio.mat_intent  = 'Aligned';
                Nio.mat0_intent = Nio.mat_intent;

                Nio.descrip = 'Deformation (templ. to. ind.)';
                create(Nio);
                Nio.dat(:,:,:,1,1) = param(i).y(:,:,:,1);
                Nio.dat(:,:,:,1,2) = param(i).y(:,:,:,2);
                Nio.dat(:,:,:,1,3) = param(i).y(:,:,:,3);
                out.def{i}         = nam;
            else
                out.def{i}         = param(i).y;
            end
            param(i).y = [];
        end
    end
end

if need_jac
    out.jac = {};
    for i=numel(param):-1:1
        if all(isfinite(w_settings(i,:)))
            dt = spm_diffeo('det',param(i).J);
            if any(strcmp('wjac',output))
                [pth,nam]   = fileparts(Nii(i).dat.fname);
                nam         = fullfile(pth,['j_' nam '.nii']);
                Nio         = nifti;
                Nio.dat     = file_array(nam,size(dt),'float32',0,1,0);
                Nio.mat     = M_avg;
                Nio.mat0    = Nio.mat;
                Nio.mat_intent  = 'Aligned';
                Nio.mat0_intent = Nio.mat_intent;

                Nio.descrip = 'Jacobian det (templ. to. ind.)';
                create(Nio);
                Nio.dat(:,:,:) = dt;
                out.jac{i}     = nam;
            else
                out.jac{i}     = dt;
            end
            clear dt
            param(i).J = [];
        end
    end
end

if need_div
    out.div = {};
    for i=1:numel(param)
        if all(isfinite(w_settings(i,:)))
            dv = spm_diffeo('div',param(i).v0);
            if any(strcmp('wdiv',output))
                [pth,nam]   = fileparts(Nii(i).dat.fname);
                nam         = fullfile(pth,['dv_' nam '.nii']);
                Nio         = nifti;
                Nio.dat     = file_array(nam,size(dv),'float32',0,1,0);
                Nio.mat     = M_avg;
                Nio.mat0    = Nio.mat;
                Nio.mat_intent  = 'Aligned';
                Nio.mat0_intent = Nio.mat_intent;

                Nio.descrip = sprintf('Div (%.3g %.3g %.3g %.3g %.3g) (%d)',w_settings(i,:)*sc,s_settings(i,1));
                create(Nio);
                Nio.dat(:,:,:) = dv;
                out.div{i}     = nam;
            else
                out.div{i}     = dv;
            end
            clear dv
        end
    end
end

if need_vel
    out.vel = {};
    for i=1:numel(param)
        if all(isfinite(w_settings(i,:)))
            if any(strcmp('wvel',output))
                [pth,nam]   = fileparts(Nii(i).dat.fname);
                nam         = fullfile(pth,['v_' nam '.nii']);
                Nio         = nifti;
                Nio.dat     = file_array(nam,[d 1 3],'float32',0,1,0);
                Nio.mat     = M_avg;
                Nio.mat0    = Nio.mat;
                Nio.mat_intent  = 'Aligned';
                Nio.mat0_intent = Nio.mat_intent;

                Nio.descrip = sprintf('Vel (%.3g %.3g %.3g %.3g %.3g) (%d)',w_settings(i,:)*sc,s_settings(i,1));
                create(Nio);
                Nio.dat(:,:,:,1,1) = param(i).v0(:,:,:,1);
                Nio.dat(:,:,:,1,2) = param(i).v0(:,:,:,2);
                Nio.dat(:,:,:,1,3) = param(i).v0(:,:,:,3);
                out.vel{i}         = nam;
            else
                out.vel{i}         = param(i).v0;
            end
        end
    end
end
spm_plot_convergence('Clear');
return;
%_______________________________________________________________________


%_______________________________________________________________________
function vol = get_transformed_images(data, param, ord)
d     = data.d;
M_avg = data.mat;
img   = data.img;
prec  = data.prec;

vol   = zeros([d numel(img)],'single');

for m=1:d(3)
    F  = cell(1,numel(img));
    Dt = cell(1,numel(img));
    Bf = cell(1,numel(img));

    mum = zeros(d(1:2),'single');

    for i=1:numel(img)
        M = img(i).mat\param(i).R*M_avg;
        if ~isempty(param(i).y)
            y     = transform_warp(M,param(i).y(:,:,m,:));
            Dt{i} = spm_diffeo('det',param(i).J(:,:,m,:,:))*abs(det(M(1:3,1:3)));
        else
            Dt{i} = ones(d(1:2),'single')*abs(det(M(1:3,1:3)));
            y     = zeros([d(1:2) 1 3],'single');
            [y(:,:,1),y(:,:,2),y(:,:,3)] = ndgrid(single(1:d(1)),single(1:d(2)),m);
            y     = transform_warp(M,y);
        end

        F{i}  = spm_diffeo('bsplins',img(i).f,y,ord);
        if ~isempty(param(i).bias)
            Bf{i} = exp(spm_diffeo('bsplins',param(i).bias,y,[1 1 1 ord(4:end)])); % Trilinear
        else
            Bf{i} = ones(d(1:2),'single');
        end

        f        = F{i};
        ebias    = Bf{i};
        dt       = Dt{i};
        scal     = Bf{i}.*Dt{i}*prec(i);
        vol(:,:,m,i) = F{i}.*scal;

    end
end

return;
%_______________________________________________________________________

%_______________________________________________________________________
function [mu,ss,nvox,D] = compute_mean(data, param, ord)
d     = data.d;
M_avg = data.mat;
img   = data.img;
prec  = data.prec;

mu   = zeros(d,'single');
nvox = zeros(numel(img),1);
ss   = zeros(numel(img),1);
if nargout>=4 % Compute gradients of template
    D  = {zeros(d,'single'),zeros(d,'single'),zeros(d,'single')};
end

for m=1:d(3)
    if nargout>=4
        Dm1  = {zeros(d(1:2),'single'),zeros(d(1:2),'single'),zeros(d(1:2),'single')};
        Dm2  = {zeros(d(1:2),'single'),zeros(d(1:2),'single'),zeros(d(1:2),'single')};
        Df   = cell(3,1);
        Db   = cell(3,1);
    end
    F  = cell(1,numel(img));
    Dt = cell(1,numel(img));
    Bf = cell(1,numel(img));
    Msk= cell(1,numel(img));

    mum = zeros(d(1:2),'single');
    mgm = zeros(d(1:2),'single');

    for i=1:numel(img)
        M = img(i).mat\param(i).R*M_avg;
        if ~isempty(param(i).y)
            y     = transform_warp(M,param(i).y(:,:,m,:));
            Dt{i} = spm_diffeo('det',param(i).J(:,:,m,:,:))*abs(det(M(1:3,1:3)));
        else
            Dt{i} = ones(d(1:2),'single')*abs(det(M(1:3,1:3)));
            y     = zeros([d(1:2) 1 3],'single');
            [y(:,:,1),y(:,:,2),y(:,:,3)] = ndgrid(single(1:d(1)),single(1:d(2)),m);
            y     = transform_warp(M,y);
        end

        if nargout>=4
            % Sample image and bias field, along with their gradients.  Gradients are
            % then transformed by multiplying with the transpose of the Jacobain matrices
            % of the deformation.
            if ~isempty(param(i).J)
                Jm = reshape(param(i).J(:,:,m,:,:),[d(1)*d(2),3,3]);
                Jm = reshape(reshape(permute(Jm,[1 2 3]),d(1)*d(2)*3,3)*M(1:3,1:3),[d(1) d(2) 3 3]);
            else
                Jm = repmat(reshape(single(M(1:3,1:3)),[1 1 3 3]),[d(1) d(2) 1 1]);
            end

            [F{i} ,d1,d2,d3]  = spm_diffeo('bsplins',img(i).f,y,ord); 
            Df{1} = Jm(:,:,1,1).*d1 + Jm(:,:,2,1).*d2 + Jm(:,:,3,1).*d3;
            Df{2} = Jm(:,:,1,2).*d1 + Jm(:,:,2,2).*d2 + Jm(:,:,3,2).*d3;
            Df{3} = Jm(:,:,1,3).*d1 + Jm(:,:,2,3).*d2 + Jm(:,:,3,3).*d3;

            if ~isempty(param(i).bias)
                [Bf{i},d1,d2,d3]  = spm_diffeo('bsplins',param(i).bias,y,[1 1 1 ord(4:end)]); % Trilinear
                Bf{i} = exp(Bf{i});
                Db{1} = Jm(:,:,1,1).*d1 + Jm(:,:,2,1).*d2 + Jm(:,:,3,1).*d3;
                Db{2} = Jm(:,:,1,2).*d1 + Jm(:,:,2,2).*d2 + Jm(:,:,3,2).*d3;
                Db{3} = Jm(:,:,1,3).*d1 + Jm(:,:,2,3).*d2 + Jm(:,:,3,3).*d3;
            else
                Bf{i} =  ones(d(1:2),'single');
                Db{1} = zeros(d(1:2),'single');
                Db{2} = zeros(d(1:2),'single');
                Db{3} = zeros(d(1:2),'single');
            end
            clear d1 d2 d3
        else
            F{i}  = spm_diffeo('bsplins',img(i).f,y,ord);
            if ~isempty(param(i).bias)
                Bf{i} = exp(spm_diffeo('bsplins',param(i).bias,y,[1 1 1 ord(4:end)])); % Trilinear
            else
                Bf{i} = ones(d(1:2),'single');
            end
        end

        msk      = isfinite(F{i}) & isfinite(Bf{i});
        Msk{i}   = msk;
        f        = F{i}(msk);
        ebias    = Bf{i}(msk);
        dt       = Dt{i}(msk);
        scal     = ebias.*dt*prec(i);
        mum(msk) = mum(msk) + f.*scal;
        mgm(msk) = mgm(msk) + ebias.*scal;

        if nargout>=4
            % For computing gradients
            Dm1{1}(msk) = Dm1{1}(msk) + (Df{1}(msk) + f.*Db{1}(msk)).*scal;
            Dm1{2}(msk) = Dm1{2}(msk) + (Df{2}(msk) + f.*Db{2}(msk)).*scal;
            Dm1{3}(msk) = Dm1{3}(msk) + (Df{3}(msk) + f.*Db{3}(msk)).*scal;

            scal        = ebias.*scal;
            Dm2{1}(msk) = Dm2{1}(msk) + Db{1}(msk).*scal;
            Dm2{2}(msk) = Dm2{2}(msk) + Db{2}(msk).*scal;
            Dm2{3}(msk) = Dm2{3}(msk) + Db{3}(msk).*scal;
        end
    end
    mgm       = mgm + eps;
    mu(:,:,m) = mum./mgm; % Weighted mean

    if nargout>=2
        if nargout>=4
            % Compute "gradients of template (mu)".  Note that the true gradients
            % would incorporate the gradients of the Jacobians, but we do not want
            % these to be part of the "template gradients".
            wt          = 2*mum./(mgm.*mgm);
            D{1}(:,:,m) = Dm1{1}./mgm - Dm2{1}.*wt;
            D{2}(:,:,m) = Dm1{2}./mgm - Dm2{2}.*wt;
            D{3}(:,:,m) = Dm1{3}./mgm - Dm2{3}.*wt;
        end

        % Compute matching term
        for i=1:numel(img)
            msk      = Msk{i};
            f        = F{i}(msk);
            ebias    = Bf{i}(msk);
            dt       = Dt{i}(msk);
            mum      = mu(:,:,m);
            mum      = mum(msk);
            nvox(i)  = nvox(i) + sum(dt);
            ss(i)    = ss(i) + sum((f-mum.*ebias).^2.*dt);
        end
    end
end

for i=1:numel(img)
    ss(i) = ss(i)/nvox(i)*numel(img(i).f);
end
return;
%_______________________________________________________________________

%_______________________________________________________________________
function y1 = transform_warp(M,y)
% Affine transformation of a deformation
d  = size(y);
y1 = reshape(bsxfun(@plus,reshape(y,[prod(d(1:3)),3])*single(M(1:3,1:3)'),single(M(1:3,4)')),d);
return;
%_______________________________________________________________________

%_______________________________________________________________________
function y = identity(d)
% Generate an identity transform of size d(1) x d(2) x d(3)
y = zeros([d(1:3) 3],'single');
[y(:,:,:,1),y(:,:,:,2),y(:,:,:,3)] = ndgrid(single(1:d(1)),single(1:d(2)),single(1:d(3)));
%_______________________________________________________________________

function [M_avg,d] = compute_avg_mat(Mat0,dims)
% Compute an average voxel-to-world mapping and suitable dimensions
% FORMAT [M_avg,d] = spm_compute_avg_mat(Mat0,dims)
% Mat0  - array of matrices (4x4xN)
% dims  - image dimensions (Nx3)
% M_avg - voxel-to-world mapping
% d     - dimensions for average image
%
%__________________________________________________________________________
% Copyright (C) 2012-2019 Wellcome Trust Centre for Neuroimaging

% John Ashburner
% $Id$


% Rigid-body matrices computed from exp(p(1)*B(:,:,1)+p(2)+B(:,:,2)...)
%--------------------------------------------------------------------------
B = se3_basis;

% Find combination of 90 degree rotations and flips that brings all
% the matrices closest to axial
%--------------------------------------------------------------------------
Matrices = Mat0;
pmatrix  = [1,2,3; 2,1,3; 3,1,2; 3,2,1; 1,3,2; 2,3,1];
for i=1:size(Matrices,3)
    vx    = sqrt(sum(Matrices(1:3,1:3,i).^2));
    tmp   = Matrices(:,:,i)/diag([vx 1]);
    R     = tmp(1:3,1:3);
    minss = Inf;
    minR  = eye(3);
    for i1=1:6
        R1 = zeros(3);
        R1(pmatrix(i1,1),1)=1;
        R1(pmatrix(i1,2),2)=1;
        R1(pmatrix(i1,3),3)=1;
        for i2=0:7
            F  = diag([bitand(i2,1)*2-1, bitand(i2,2)-1, bitand(i2,4)/2-1]);
            R2 = F*R1;
            ss = sum(sum((R/R2-eye(3)).^2));
            if ss<minss
                minss = ss;
                minR  = R2;
            end
        end
    end
    rdim = abs(minR*dims(i,:)');
    R2   = inv(minR);
    minR = [R2 R2*((sum(R2,1)'-1)/2.*(rdim+1)); 0 0 0 1];
    Matrices(:,:,i) = Matrices(:,:,i)*minR;
end

% Average of these matrices
%--------------------------------------------------------------------------
M_avg = spm_meanm(Matrices);

% If average involves shears, then find the closest matrix that does not
% require them
%--------------------------------------------------------------------------
p = spm_imatrix(M_avg);
if sum(p(10:12).^2)>1e-8

    % Zooms computed from exp(p(7)*B2(:,:,1)+p(8)*B2(:,:,2)+p(9)*B2(:,:,3))
    %----------------------------------------------------------------------
    B2        = zeros(4,4,3);
    B2(1,1,1) = 1;
    B2(2,2,2) = 1;
    B2(3,3,3) = 1;

    p      = zeros(9,1); % Parameters
    for it=1:10000
        [R,dR] = spm_dexpm(p(1:6),B);  % Rotations + Translations
        [Z,dZ] = spm_dexpm(p(7:9),B2); % Zooms

        M  = R*Z; % Voxel-to-world estimate
        dM = zeros(4,4,6);
        for i=1:6, dM(:,:,i)   = dR(:,:,i)*Z; end
        for i=1:3, dM(:,:,i+6) = R*dZ(:,:,i); end
        dM = reshape(dM,[16,9]);

        d   = M(:)-M_avg(:); % Difference
        gr  = dM'*d;         % Gradient
        Hes = dM'*dM;        % Hessian
        p   = p - Hes\gr;    % Gauss-Newton update
        if sum(gr.^2)<1e-8, break; end
    end
    M_avg = M;
end

% Ensure that the FoV covers all images, with a few voxels to spare
%--------------------------------------------------------------------------
mn    =  Inf*ones(3,1);
mx    = -Inf*ones(3,1);
for i=1:size(Mat0,3)
    dm      = [dims(i,:) 1 1];
    corners = [
        1 dm(1)    1  dm(1)   1  dm(1)    1  dm(1)
        1    1  dm(2) dm(2)   1     1  dm(2) dm(2)
        1    1     1     1 dm(3) dm(3) dm(3) dm(3)
        1    1     1     1    1     1     1     1];
    M  = M_avg\Mat0(:,:,i);
    vx = M(1:3,:)*corners;
    mx = max(mx,max(vx,[],2));
    mn = min(mn,min(vx,[],2));
end
mx    = ceil(mx);
mn    = floor(mn);
d     = (mx-mn+7)';
M_avg = M_avg * [eye(3) mn-4; 0 0 0 1];
return;
%__________________________________________________________________________

%__________________________________________________________________________
function B = se3_basis
% Basis functions for the lie algebra of the special Euclidean group
% (SE(3)).
B        = zeros(4,4,6);
B(1,4,1) = 1;
B(2,4,2) = 1;
B(3,4,3) = 1;
B([1,2],[1,2],4) = [0 1;-1 0];
B([3,1],[3,1],5) = [0 1;-1 0];
B([2,3],[2,3],6) = [0 1;-1 0];
return;
%__________________________________________________________________________



%_______________________________________________________________________
function t = transf(B1,B2,B3,T)
d2 = [size(T) 1];
t1 = reshape(reshape(T, d2(1)*d2(2),d2(3))*B3', d2(1), d2(2));
t  = B1*t1*B2';
return;
%_______________________________________________________________________

%_______________________________________________________________________
function dat = bias_correction(volG,volF,brainmask,pyramid,nits,fwhm,reg1,reg2)
% This function is intended for doing bias correction between scans inside a defined mask
% A version of the second image is returned out, that has the
% same bias as that of the first image.  

vx      = sqrt(sum(pyramid.mat(1:3,1:3).^2));
d       = size(volG);
sd      = vx(1)*size(volG,1)/fwhm; d3(1) = ceil(sd*2); krn_x   = exp(-(0:(d3(1)-1)).^2/sd.^2)/sqrt(vx(1));
sd      = vx(2)*size(volG,2)/fwhm; d3(2) = ceil(sd*2); krn_y   = exp(-(0:(d3(2)-1)).^2/sd.^2)/sqrt(vx(2));
sd      = vx(3)*size(volG,3)/fwhm; d3(3) = ceil(sd*2); krn_z   = exp(-(0:(d3(3)-1)).^2/sd.^2)/sqrt(vx(3));
Cbias   = kron(krn_z,kron(krn_y,krn_x)).^(-2)*prod(d)*reg1;
Cbias   = sparse(1:length(Cbias),1:length(Cbias),Cbias,length(Cbias),length(Cbias));
B3bias  = spm_dctmtx(d(3),d3(3));
B2bias  = spm_dctmtx(d(2),d3(2));
B1bias  = spm_dctmtx(d(1),d3(1));
lmRb    = speye(size(Cbias))*prod(d)*reg2;
Tbias   = zeros(d3);

% correct global scaling
thG = mean(volG(isfinite(volG)))/8; thG = mean(volG(volG>thG));
thF = mean(volF(isfinite(volF)))/8; thF = mean(volF(volF>thF));
volF = volF*thG/thF;
thF = mean(volF(isfinite(volF)))/8; thF = mean(volF(volF>thF));

ll = Inf;
spm_plot_convergence('Init','Bias Correction','- Log-likelihood','Iteration');

for subit=1:nits

    % Compute objective function and its 1st and second derivatives
    Alpha = zeros(prod(d3),prod(d3)); % Second derivatives
    Beta  = zeros(prod(d3),1); % First derivatives
    oll   = ll;
    ll    = 0.5*Tbias(:)'*Cbias*Tbias(:);

    for z=1:size(volG,3)
        f1o = volF(:,:,z);
        f2o = volG(:,:,z);
        f1o(~isfinite(f1o)) = 0;
        f2o(~isfinite(f2o)) = 0;
        if ~isempty(brainmask)
          msk = ((f1o==0) & (f2o==0)) & (brainmask(:,:,z) < 0.25);
        else
          msk = (f1o==0) & (f2o==0);
        end
        f1o(msk) = 0;
        f2o(msk) = 0;
        ro       = transf(B1bias,B2bias,B3bias(z,:),Tbias);
        msk      = abs(ro)>0.01; 

        % Use the form based on an integral for bias that is
        % far from uniform.
        f1  = f1o(msk);
        f2  = f2o(msk);
        r   = ro(msk);
        e   = exp(r);
        t1  = (f2.*e-f1);
        t2  = (f1./e-f2);
        ll  = ll + 1/4*sum(sum((t1.^2-t2.^2)./r));
        wt1 = zeros(size(f1o));
        wt2 = zeros(size(f1o));
        wt1(msk) = (2*(t1.*f2.*e+t2.*f1./e)./r + (t2.^2-t1.^2)./r.^2)/4;
        wt2(msk) = ((f2.^2.*e.^2-f1.^2./e.^2+t1.*f2.*e-t2.*f1./e)./r/2 ...
                 - (t1.*f2.*e+t2.*f1./e)./r.^2 + (t1.^2-t2.^2)./r.^3/2);

        % Use the simple symmetric form for bias close to uniform
        f1  = f1o(~msk);
        f2  = f2o(~msk);
        r   = ro(~msk);
        e   = exp(r);
        t1  = (f2.*e-f1);
        t2  = (f1./e-f2);
        ll  = ll + (sum(t1.^2)+sum(t2.^2))/4;
        wt1(~msk) = (t1.*f2.*e-t2.*f1./e)/2;
        wt2(~msk) = ((f2.*e).^2+t1.*f2.*e + (f1./e).^2+t2.*f1./e)/2;

        b3    = B3bias(z,:)';
        Beta  = Beta  + kron(b3,spm_krutil(wt1,B1bias,B2bias,0));
        Alpha = Alpha + kron(b3*b3',spm_krutil(wt2,B1bias,B2bias,1));
    end;
    try
        spm_plot_convergence('Set',ll/prod(d));
    catch
        spm_chi2_plot('Set',ll/prod(d));
    end

    % temporarily estimate whole bias field to check for huge values
    r3 = zeros(size(volG));
    for z=1:size(volG,3)
        r3(:,:,z)  = transf(B1bias,B2bias,B3bias(z,:),Tbias);
    end;
    
    % additionally check if 1./exp(r3) is getting too large and regularization
    % should be increased
    % "-4" equals roughly to a max value of 50 for 1./exp(r3)
    if (subit > 1 && ll>oll) || min(r3(:)) < -4
        % Hasn't improved, so go back to previous solution
        Tbias = oTbias;
        ll    = oll;
        lmRb  = lmRb*10;
    else
        % Accept new solution
        oTbias = Tbias;
        Tbias  = Tbias(:);
        Tbias  = Tbias - (Alpha + Cbias + lmRb)\(Beta + Cbias*Tbias);
        Tbias  = reshape(Tbias,d3);
    end;

end;

dat = zeros(size(volG));

for z=1:size(volG,3)
    tmp = volF(:,:,z);
    tmp(~isfinite(tmp)) = 0;
    dat(:,:,z) = tmp;
    r  = transf(B1bias,B2bias,B3bias(z,:),Tbias);
    r(volG(:,:,z) == 0) = 0;
    dat(:,:,z) = dat(:,:,z)./exp(r);
end;

return;
%_______________________________________________________________________
