function test_suite=test_fmri_io
    initTestSuite;

function test_fmri_io_base
    x_base=get_base_dataset();

    x=x_base;
    exts={'.nii.gz', '.nii', '.hdr', '.img', '+orig.HEAD',...
              '+tlrc.BRIK','.vmp',...
              '.vmr', '.msk', '.mat'};

    skips=struct();

    skips.nii_gz.description='.nii.gz (gzipped) NIFTI';
    skips.nii_gz.matcher=@()~usejava('jvm');
    skips.nii_gz.exts={'.nii.gz'};
    skips.nii_gz.component='java VM';

    skips.afni.description='AFNI';
    skips.afni.matcher=@()~cosmo_check_external('afni',false);
    skips.afni.exts={'+orig.HEAD','+tlrc.BRIK'};
    skips.afni.component='external ''afni''';

    skips.bv.description='BrainVoyager';
    skips.bv.matcher=@()cosmo_wtf('is_octave') || ...
                    ~cosmo_check_external('neuroelf',false);
    skips.bv.component='external ''neuroelf''';
    skips.bv.exts={'.vmp','.vmr','.msk'};

    skip_keys=fieldnames(skips);
    nskip_keys=numel(skip_keys);
    skipped_fieldname=[];

    n=numel(exts);
    for k=1:n
        ext=exts{k};

        skip_test=false;
        for j=1:nskip_keys
            s=skips.(skip_keys{j});
            if cosmo_match({ext},s.exts) && s.matcher()
                skipped_fieldname=skip_keys{j};
                skip_test=true;
                break;
            end
        end

        if skip_test
            continue;
        end

        y=save_and_load(x_base,ext);
        assert_dataset_equal(x,y,ext);
    end


    if ~isempty(skipped_fieldname)
        s=skips.(skipped_fieldname);
        reason=sprintf(['fmri i/o for %s files skipped because %s'...
                        'is not available'],...
                        s.description,s.component);

        cosmo_notify_test_skipped(reason);
    end

function test_fmri_io_exceptions()
    aet=@(varargin)assertExceptionThrown(@()...
                            cosmo_fmri_dataset(varargin{:}),'');

    fn=get_temp_filename('test%d.mat');
    fn2=get_temp_filename('test%d+orig.HEAD');
    cleaner=onCleanup(@()delete_files({fn}));

    x=struct();
    save(fn,'x');
    aet(fn);

    x=1;
    y=1;
    save(fn,'x','y');
    aet(fn);

    % incomplete AFNI struct
    x=struct();
    x.DATASET_DIMENSIONS=[];
    x.DATASET_RANK=[];
    aet(x);

    % illegal AFNI file
    save(fn2,'x');
    aet(fn2);

    % wrong dimension size
    ds=cosmo_synthetic_dataset();
    afni=cosmo_map2fmri(ds,'-afni');
    afni.img=zeros(1,1,1,1,5);
    aet(afni);

function test_fmri_io_mask
    aet=@(varargin)assertExceptionThrown(@()...
                    cosmo_fmri_dataset(varargin{:}),'');

    ds=cosmo_synthetic_dataset();
    ds.sa=struct();
    m=cosmo_slice(ds,1);

    fn=get_temp_filename('test%d.nii');
    fn2=get_temp_filename('test2_%d.nii');

    cleaner=onCleanup(@()delete_files({fn,fn2}));

    cosmo_map2fmri(ds,fn);
    cosmo_map2fmri(m,fn2);
    x=cosmo_fmri_dataset(fn,'mask',fn2);
    assert_dataset_equal(x,ds,'.nii')

    m_rsa=cosmo_fmri_reorient(m,'RSA');
    cosmo_map2fmri(m_rsa,fn2);
    x=cosmo_fmri_dataset(fn,'mask',fn2);
    assert_dataset_equal(x,ds,'.nii')

    m_bad_fa=m;
    m_bad_fa.a.fdim.values{1}=[1 2 3 4];
    m_bad_fa.a.vol.dim(1)=4;
    m_bad_fa.fa.i=m.fa.i+1;
    cosmo_map2fmri(m_bad_fa,fn2);
    aet(fn,'mask',fn2);

    m_bad_mat=m;
    m_bad_mat.a.vol.mat(1)=3;
    cosmo_map2fmri(m_bad_mat,fn2);
    aet(fn,'mask',fn2);

    m_bad_2samples=cosmo_stack({m,m});
    cosmo_map2fmri(m_bad_2samples,fn2);
    aet(fn,'mask',fn2);

    % disable automask warning
    warning_state=cosmo_warning();
    state_resetter=onCleanup(@()cosmo_warning(warning_state));
    cosmo_warning('off');

    ds.samples(:,1:5)=0;
    ds.samples(1,1)=1;

    res=cosmo_fmri_dataset(ds,'mask','');
    assertEqual(res,ds);







function assert_dataset_equal(x,y,ext)
    funcs={@assert_samples_equal, @assert_a_equal, ...
                    @assert_fa_equal,...
                    @assert_sa_equal};
    for j=1:numel(funcs)
        func=funcs{j};
        func(x,y,ext);
    end

function assert_samples_equal(x,y,ext)
    xs=x.samples;
    ys=y.samples;
    switch ext
        case '.msk'
            assert(cosmo_corr(xs',ys')>.999);
        case '.vmr'
            assert(cosmo_corr(xs',ys')>.999);
        otherwise
            assertElementsAlmostEqual(xs,ys,'relative',1e-5);
    end


function assert_a_equal(xd,yd,ext)
    x=xd.a;
    y=yd.a;
    x.vol=rmfield_if_present(x.vol,'xform');
    y.vol=rmfield_if_present(y.vol,'xform');

    switch ext
        case '.vmr'
            % does not store the offset, so do not check it
            x.vol.mat=x.vol.mat(:,1:3);
            y.vol.mat=y.vol.mat(:,1:3);
        otherwise
            % keep as is
    end

    assertEqual(x,y);

function assert_fa_equal(x,y,ext)
    assertEqual(x.fa,y.fa);

function assert_sa_equal(x,y,ext)
    ignore_sa_exts={'.nii','.nii.gz','.hdr','.img','.vmr','.msk'};
    if cosmo_match({ext},ignore_sa_exts)
        return;
    end

    assertEqual(x.sa,y.sa);


function s=rmfield_if_present(s, f)
    if isfield(s,f)
        s=rmfield(s,f);
    end


function x=get_base_dataset()
    x=cosmo_synthetic_dataset('size','big');
    x=cosmo_fmri_reorient(x,'ASR');
    x=cosmo_slice(x,1);
    x.sa=struct();
    x.sa.labels={'labels1'};
    x.sa.stats={'Ttest(17)'};

function ds_again=save_and_load(ds,ext)
    pat=['tmp%d' ext];
    fn=get_temp_filename(pat);
    fn2=get_sibling(fn,ext);
    cleaner=onCleanup(@()delete_files({fn,fn2}));

    switch ext
        case '.mat'
            save(fn,'ds');
        otherwise
            % disable automask warning
            warning_state=cosmo_warning();
            state_resetter=onCleanup(@()cosmo_warning(warning_state));
            cosmo_warning('off');

            cosmo_map2fmri(ds,fn);
    end

    ds_again=cosmo_fmri_dataset(fn);

function sib_fn=get_sibling(fn,ext)
    switch ext
        case '.img'
            sib_ext='hdr';
        case '.hdr'
            sib_ext='img';
        case '+orig.HEAD'
            sib_ext='+orig.BRIK';
        case '+orig.BRIK'
            sib_ext='+orig.HEAD';
        case '+tlrc.HEAD'
            sib_ext='+tlrc.BRIK';
        case '+tlrc.BRIK'
            sib_ext='+tlrc.HEAD';
        otherwise
            sib_fn=[];
            return
    end

    sib_fn=strrep(fn,ext,sib_ext);


function delete_files(fns)
    for k=1:numel(fns)
        fn=fns{k};
        if ~isempty(fn) && exist(fn,'file')
            delete(fn);
        end
    end

function temp_path=get_temp_path()
    c=cosmo_config();
    if ~isfield(c,'temp_path')
        error('temp_path is not set in cosmo_config');
    end
    temp_path=c.temp_path;

function fn=get_temp_filename(pat)
    if ~any(pat=='%')
        error('pattern must contain numeric identifier');
    end
    temp_path=get_temp_path();
    k=0;
    while true
        fn=fullfile(temp_path,sprintf(pat,k));
        if ~exist(fn,'file')
            return;
        end
        k=k+1;
    end
