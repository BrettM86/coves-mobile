/// Constants used in atProto identity resolution.
library;

/// Placeholder handle used when handle is invalid or doesn't match DID.
const String handleInvalid = 'handle.invalid';

/// DID prefix for all decentralized identifiers.
const String didPrefix = 'did:';

/// DID PLC (Placeholder) prefix.
const String didPlcPrefix = 'did:plc:';

/// DID Web prefix.
const String didWebPrefix = 'did:web:';

/// Length of a complete did:plc identifier (including prefix).
const int didPlcLength = 32;

/// Default PLC directory URL for resolving did:plc identifiers.
const String defaultPlcDirectoryUrl = 'https://plc.directory/';

/// Maximum length for a DID (per spec).
const int maxDidLength = 2048;

/// atProto service type in DID documents.
const String atprotoServiceType = 'AtprotoPersonalDataServer';

/// atProto service ID prefix in DID documents.
const String atprotoServiceId = '#atproto_pds';
