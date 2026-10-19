/*
 * The administrator gate, defined once for this Module. People's entry point
 * deliberately does not export `requireAdmin`/`isAdmin` (ADR-0006), so each
 * Module carries its own copy, but one per Module rather than one per route
 * file.
 */

function requireAdmin(req, res, next) {
  if (req.account.role !== 'admin') {
    return res.status(403).json({ message: 'This action requires the administrator role.' });
  }
  return next();
}

module.exports = { requireAdmin };
