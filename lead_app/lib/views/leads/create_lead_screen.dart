import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/lead_service.dart';
import '../../models/lead_model.dart';
import '../../models/voice_note_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/lead_provider.dart';
import 'widgets/voice_note_recorder_widget.dart';

class CreateLeadScreen extends StatefulWidget {
  final LeadModel? editingLead;

  const CreateLeadScreen({super.key, this.editingLead});

  @override
  State<CreateLeadScreen> createState() => _CreateLeadScreenState();
}

class _CreateLeadScreenState extends State<CreateLeadScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _stateController = TextEditingController();

  final _totalRoomsController = TextEditingController();
  final _roomPriceController = TextEditingController();
  final _onlineRoomsController = TextEditingController();
  final _offlineRoomsController = TextEditingController();

  final _ownerNameController = TextEditingController();
  final _phoneController = TextEditingController();

  final _notesController = TextEditingController();
  final _agentNotesController = TextEditingController();

  VoiceNoteModel? _meetingNotesAudio;
  VoiceNoteModel? _agentNotesAudio;

  // Location
  double? _lat;
  double? _lng;
  bool _isLocating = false;
  String? _locationStatus;

  // Interest & Meeting
  String _interest = 'Interested';
  bool _meetingRequested = true;
  DateTime? _meetingDateTime;
  String _meetingMode = 'Call';

  // Images
  final List<String> _photos = [];
  bool _isUploadingPhoto = false;

  final ImagePicker _picker = ImagePicker();
  final LeadService _leadService = LeadService();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() {
    final lead = widget.editingLead;
    final agent = context.read<AuthProvider>().user;

    if (lead != null) {
      _nameController.text = lead.name;
      _addressController.text = lead.address;
      _cityController.text = lead.city;
      _districtController.text = lead.district;
      _stateController.text = lead.state;

      _totalRoomsController.text = lead.totalRooms?.toString() ?? '';
      _roomPriceController.text = lead.roomPrice?.toString() ?? '';
      _onlineRoomsController.text = lead.onlineRooms?.toString() ?? '';
      _offlineRoomsController.text = lead.offlineRooms?.toString() ?? '';

      _ownerNameController.text = lead.ownerName;
      _phoneController.text = lead.phone;

      _notesController.text = lead.notes;
      _agentNotesController.text = lead.agentNotes;
      _meetingNotesAudio = lead.meetingNotesAudio;
      _agentNotesAudio = lead.agentNotesAudio;

      _interest = lead.interest;
      _meetingRequested = lead.meetingRequested;
      _meetingMode = lead.meetingMode.isNotEmpty ? lead.meetingMode : 'Call';
      if (lead.meetingTime.isNotEmpty) {
        try {
          _meetingDateTime = DateTime.parse(lead.meetingTime).toLocal();
        } catch (_) {}
      }

      _lat = lead.lat;
      _lng = lead.lng;
      _photos.addAll(lead.images);
    } else {
      // Default city/district/state from logged-in agent jurisdiction
      final defaultCity = agent?.city ?? agent?.district ?? 'Mathura';
      final defaultDistrict = agent?.district ?? 'Mathura';
      final defaultState = agent?.state ?? 'Uttar Pradesh';

      _cityController.text = defaultCity;
      _districtController.text = defaultDistrict;
      _stateController.text = defaultState;

      // Automatically capture GPS location for fresh lead
      _captureLocation();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _stateController.dispose();
    _totalRoomsController.dispose();
    _roomPriceController.dispose();
    _onlineRoomsController.dispose();
    _offlineRoomsController.dispose();
    _ownerNameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _agentNotesController.dispose();
    super.dispose();
  }

  Future<void> _captureLocation() async {
    setState(() {
      _isLocating = true;
      _locationStatus = 'Detecting satellite GPS coordinates...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLocating = false;
          _locationStatus =
              'GPS is disabled. Please turn on Location in settings.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLocating = false;
            _locationStatus = 'Location permission denied.';
          });
          return;
        }
      }

      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        pos =
            lastKnown ??
            Position(
              latitude: 27.5144,
              longitude: 77.6741,
              timestamp: DateTime.now(),
              accuracy: 10.0,
              altitude: 0.0,
              altitudeAccuracy: 0.0,
              heading: 0.0,
              headingAccuracy: 0.0,
              speed: 0.0,
              speedAccuracy: 0.0,
            );
      }

      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _isLocating = false;
        _locationStatus =
            'GPS Fixed: (${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})';
      });
    } catch (e) {
      setState(() {
        _isLocating = false;
        _locationStatus = 'GPS Error: ${e.toString()}';
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );

      if (file == null) return;

      setState(() => _isUploadingPhoto = true);

      try {
        final url = await _leadService.uploadImage(
          file,
          isCamera: source == ImageSource.camera,
        );
        setState(() {
          _photos.add(url);
          _isUploadingPhoto = false;
        });
      } catch (_) {
        // In offline mode, store local file path
        setState(() {
          _photos.add(file.path);
          _isUploadingPhoto = false;
        });
      }
    } catch (_) {
      setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _selectMeetingDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _meetingDateTime ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );

    if (pickedDate != null && mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: _meetingDateTime != null
            ? TimeOfDay.fromDateTime(_meetingDateTime!)
            : const TimeOfDay(hour: 11, minute: 0),
      );

      if (pickedTime != null) {
        setState(() {
          _meetingDateTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  void _saveLead() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    final agent = context.read<AuthProvider>().user;
    final leadProvider = context.read<LeadProvider>();

    final defaultCity = agent?.city ?? agent?.district ?? 'Mathura';
    final defaultDistrict = agent?.district ?? 'Mathura';
    final defaultState = agent?.state ?? 'Uttar Pradesh';

    final lead = LeadModel(
      id: widget.editingLead?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      address: _addressController.text.trim(),
      city: _cityController.text.trim().isNotEmpty
          ? _cityController.text.trim()
          : defaultCity,
      district: _districtController.text.trim().isNotEmpty
          ? _districtController.text.trim()
          : defaultDistrict,
      state: _stateController.text.trim().isNotEmpty
          ? _stateController.text.trim()
          : defaultState,
      lat: _lat,
      lng: _lng,
      totalRooms: int.tryParse(_totalRoomsController.text),
      roomPrice: double.tryParse(_roomPriceController.text),
      onlineRooms: int.tryParse(_onlineRoomsController.text),
      offlineRooms: int.tryParse(_offlineRoomsController.text),
      ownerName: _ownerNameController.text.trim(),
      phone: _phoneController.text.trim(),
      notes: _notesController.text.trim(),
      agentNotes: _agentNotesController.text.trim(),
      meetingNotesAudio: _meetingNotesAudio,
      agentNotesAudio: _agentNotesAudio,
      interest: _interest,
      meetingRequested: _meetingRequested,
      meetingTime: _meetingDateTime?.toIso8601String() ?? '',
      meetingMode: _meetingMode,
      images: _photos,
      status: widget.editingLead?.status ?? 'pending',
      capturedByName: agent?.name ?? '',
      createdAt:
          widget.editingLead?.createdAt ?? DateTime.now().toIso8601String(),
    );

    bool success;
    if (widget.editingLead != null) {
      success = await leadProvider.updateLead(lead);
    } else {
      success = await leadProvider.createLead(lead);
    }

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(
              widget.editingLead != null
                  ? 'Lead updated successfully'
                  : 'Lead submitted for verification!',
            ),
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.warning,
            content: Text(
              'Lead saved locally (offline). It will sync when connected.',
            ),
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editingLead != null;
    final agent = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          isEdit ? 'Edit Stay Lead' : 'New Stay Onboarding Lead',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            // GPS Location Card
            _buildLocationCard(),
            const SizedBox(height: 16),

            // Ashram Details
            _buildSection(
              title: 'Stay / Property Details',
              icon: Icons.hotel_outlined,
              children: [
                _buildTextField(
                  controller: _nameController,
                  label: 'Stay Name *',
                  hint: 'e.g. Parmarth Niketan Stay',
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Stay name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _addressController,
                  label: 'Complete Address / Landmark',
                  hint: 'Near Ram Jhula, Swargashram',
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Assigned Jurisdiction: ${_cityController.text.isNotEmpty ? _cityController.text : (agent?.city ?? agent?.district ?? "Mathura")}, ${_districtController.text.isNotEmpty ? _districtController.text : (agent?.district ?? "Mathura")}, ${_stateController.text.isNotEmpty ? _stateController.text : (agent?.state ?? "Uttar Pradesh")}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Room Inventory & Pricing
            _buildSection(
              title: 'Room Inventory & Tariff',
              icon: Icons.hotel_outlined,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _totalRoomsController,
                        label: 'Total Rooms',
                        hint: 'e.g. 50',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _roomPriceController,
                        label: 'Avg Tariff (₹/Night)',
                        hint: 'e.g. 1500',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _onlineRoomsController,
                        label: 'Proposed Online Rooms',
                        hint: 'e.g. 20',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _offlineRoomsController,
                        label: 'Offline Rooms',
                        hint: 'e.g. 30',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Contact Person Details
            _buildSection(
              title: 'Owner / Management Contact',
              icon: Icons.person_outline,
              children: [
                _buildTextField(
                  controller: _ownerNameController,
                  label: 'Owner / Mahant / Manager Name *',
                  hint: 'Swami Ramanand Ji',
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Contact name required'
                      : null,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _phoneController,
                  label: 'Contact Phone Number *',
                  hint: '10-digit mobile number',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: (v) => v == null || v.length < 10
                      ? 'Enter valid 10-digit number'
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Interest & Follow-up Meeting
            _buildSection(
              title: 'Owner Interest & Meeting Request',
              icon: Icons.handshake_outlined,
              children: [
                const Text(
                  'Owner Interest Level',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppConstants.interests.map((it) {
                    final isSelected = _interest == it;
                    return ChoiceChip(
                      label: Text(it),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _interest = it);
                      },
                      selectedColor: AppColors.primaryLight,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        fontSize: 12,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Meeting toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Schedule Follow-up Meeting',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Set date and mode with Tirvona onboarding executive',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  value: _meetingRequested,
                  activeTrackColor: AppColors.primary,
                  onChanged: (val) => setState(() => _meetingRequested = val),
                ),

                if (_meetingRequested) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _selectMeetingDateTime,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _meetingDateTime != null
                                  ? DateFormat('EEEE, dd MMM yyyy - hh:mm a')
                                        .format(_meetingDateTime!)
                                  : 'Select Meeting Date & Time',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _meetingDateTime != null
                                    ? AppColors.textPrimary
                                    : AppColors.textMuted,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: AppConstants.meetingModes.map((mode) {
                      final isSelected = _meetingMode == mode;
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(
                            right: mode == 'Call' ? 8 : 0,
                          ),
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: isSelected
                                  ? AppColors.primaryLight
                                  : AppColors.background,
                              side: BorderSide(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: Icon(
                              mode == 'Call'
                                  ? Icons.phone_in_talk_outlined
                                  : Icons.group_outlined,
                              size: 16,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                            label: Text(
                              mode,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                            onPressed: () =>
                                setState(() => _meetingMode = mode),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // Discussion & Notes (Voice Recording & STT)
            _buildSection(
              title: 'Discussion Notes & Observations',
              icon: Icons.mic_outlined,
              children: [
                VoiceNoteRecorderWidget(
                  label: 'Meeting / Discussion Notes',
                  hint: 'Tap to record owner discussion, tariff, facilities...',
                  type: 'meeting',
                  isPrivate: false,
                  initialVoiceNote: _meetingNotesAudio,
                  initialTranscript: _notesController.text,
                  onChanged: (vn, transcript) {
                    setState(() {
                      _meetingNotesAudio = vn;
                      _notesController.text = transcript;
                    });
                  },
                ),
                const SizedBox(height: 14),
                VoiceNoteRecorderWidget(
                  label: 'Internal Agent Notes (Private)',
                  hint: 'Tap to record private verification, roads, issues...',
                  type: 'internal',
                  isPrivate: true,
                  initialVoiceNote: _agentNotesAudio,
                  initialTranscript: _agentNotesController.text,
                  onChanged: (vn, transcript) {
                    setState(() {
                      _agentNotesAudio = vn;
                      _agentNotesController.text = transcript;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Photos Section
            _buildSection(
              title: 'Stay Photos (${_photos.length}/10)',
              icon: Icons.camera_alt_outlined,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text(
                          'Take Photo',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _isUploadingPhoto
                            ? null
                            : () => _pickImage(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 16,
                        ),
                        label: const Text(
                          'Gallery',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _isUploadingPhoto
                            ? null
                            : () => _pickImage(ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                if (_isUploadingPhoto) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(color: AppColors.primary),
                ],
                if (_photos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final pathOrUrl = _photos[i];
                        final isRemote = pathOrUrl.startsWith('http');
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: isRemote
                                  ? Image.network(
                                      pathOrUrl,
                                      width: 90,
                                      height: 90,
                                      fit: BoxFit.cover,
                                    )
                                  : Image.file(
                                      File(pathOrUrl),
                                      width: 90,
                                      height: 90,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _photos.removeAt(i)),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 28),

            // Submit Button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _saveLead,
                child: Text(
                  isEdit ? 'Update Stay Lead' : 'Submit Lead for Verification',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.my_location, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Physical Location Verification',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: _isLocating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : const Icon(
                        Icons.refresh,
                        size: 18,
                        color: AppColors.primary,
                      ),
                onPressed: _isLocating ? null : _captureLocation,
                tooltip: 'Refresh GPS',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              children: [
                Icon(
                  _lat != null
                      ? Icons.check_circle
                      : Icons.satellite_alt_outlined,
                  size: 16,
                  color: _lat != null ? AppColors.success : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _locationStatus ??
                        (_lat != null
                            ? 'Lat: ${_lat!.toStringAsFixed(5)}, Lng: ${_lng!.toStringAsFixed(5)}'
                            : 'Click refresh to capture coordinates'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _lat != null
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
