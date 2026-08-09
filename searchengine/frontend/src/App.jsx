import React, { useCallback, useMemo, useState } from 'react';
import './App.css';
import '@fontsource/roboto/400.css';
import {
  Box,
  Button,
  CircularProgress,
  Grid,
  Link,
  MenuItem,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableRow,
  TextField,
} from '@mui/material';


const API_BASE = 'https://libc.rip/api';
const DEFAULT_LIMIT = 10;
const PAGE_SIZE_OPTIONS = [10, 25, 50, 100];

const api = async (path, data, params = {}) => {
  const query = new URLSearchParams();

  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null) {
      query.set(key, value);
    }
  });

  const url = query.toString() ? `${API_BASE}${path}?${query.toString()}` : `${API_BASE}${path}`;
  let resp = await fetch(url, {
    method: 'POST',
    mode: 'cors',
    cache: 'no-cache',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(data),
  });
  return await resp.json();
};

const createRow = () => ({
  id: globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(16).slice(2)}`,
  symbol: '',
  address: '',
  addressValid: true,
});

const isHexAddress = (value) => /^(0x)?[0-9a-fA-F]*$/.test(value);

const isEmptyRow = (row) => !row.symbol && !row.address;

const normalizeRows = (rows) => {
  if (rows.length === 0) {
    return [createRow()];
  }

  let nextRows = rows;

  while (
    nextRows.length > 1 &&
    isEmptyRow(nextRows[nextRows.length - 1]) &&
    isEmptyRow(nextRows[nextRows.length - 2])
  ) {
    nextRows = nextRows.slice(0, -1);
  }

  if (!isEmptyRow(nextRows[nextRows.length - 1])) {
    nextRows = nextRows.concat(createRow());
  }

  return nextRows;
};


function SearchRow({ symbol, address, addressValid, onSymbolChange, onAddressChange, onRemove }) {
  const handleSymbolChange = useCallback((evt) => {
    onSymbolChange(evt.target.value);
  }, [onSymbolChange]);

  const handleAddressChange = useCallback((evt) => {
    const value = evt.target.value;
    onAddressChange(value, isHexAddress(value));
  }, [onAddressChange]);

  return (
    <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1.5} sx={{ alignItems: 'flex-start' }}>
      <TextField
        fullWidth
        label="Symbol name"
        value={symbol}
        onChange={handleSymbolChange}
        size="small"
      />
      <TextField
        fullWidth
        label="Address"
        error={!addressValid}
        value={address}
        onChange={handleAddressChange}
        size="small"
      />
      <Button variant="outlined" color="secondary" onClick={onRemove} sx={{ mt: { xs: 0, sm: '2px' } }}>
        Remove
      </Button>
    </Stack>
  );
}

function SearchForm({ onSearch = () => {} }) {
  const [rows, setRows] = useState(() => [createRow()]);

  const updateRow = useCallback((id, patch) => {
    setRows((currentRows) => {
      const nextRows = currentRows.map((row) => (
        row.id === id
          ? {
              ...row,
              ...patch,
              addressValid: patch.address !== undefined ? isHexAddress(patch.address) : row.addressValid,
            }
          : row
      ));

      return normalizeRows(nextRows);
    });
  }, []);

  const removeRow = useCallback((id) => {
    setRows((currentRows) => normalizeRows(currentRows.filter((row) => row.id !== id)));
  }, []);

  const onSubmit = useCallback(() => {
    let symbols = {};
    for (let row of rows) {
      if (row.addressValid && row.address && row.symbol) {
        symbols[row.symbol] = row.address;
      }
    }
    onSearch({"symbols": symbols});
  }, [rows, onSearch]);

  const isValid = useMemo(() => {
    let count = 0;
    for (let row of rows) {
      if (!row.addressValid) {
        return false;
      }
      if (row.address && row.symbol) {
        count += 1;
      }
    }
    return count > 0;
  }, [rows]);

  return (
    <Box component="form" sx={{ display: 'grid', gap: 2 }}>
      {rows.map((row) => (
        <SearchRow
          key={row.id}
          symbol={row.symbol}
          address={row.address}
          addressValid={row.addressValid}
          onSymbolChange={(symbol) => updateRow(row.id, { symbol })}
          onAddressChange={(address, addressValid) => updateRow(row.id, { address, addressValid })}
          onRemove={() => removeRow(row.id)}
        />
      ))}

      <div>
        <Button
          disabled={!isValid}
          variant="contained"
          type="button"
          className="findbutton"
          color="primary"
          onClick={onSubmit}>
          Find
        </Button>
      </div>
    </Box>
  );
}

function Result({ id, buildid, md5, symbols, download_url, symbols_url }) {
  const [open, setOpen] = useState(false);

  const onToggle = useCallback((evt) => {
    evt.preventDefault();
    setOpen((value) => !value);
  }, []);

  const symbolRows = Object.entries(symbols ?? {}).map(([k, v]) => (
    <TableRow key={k}>
      <TableCell><code>{k}</code></TableCell>
      <TableCell><code>{v}</code></TableCell>
    </TableRow>
  ));

  return (
    <Box sx={{ mb: 1 }}>
      <Link href='#' onClick={onToggle}>{id}</Link>
      {open && (
        <Table size="small" sx={{ mt: 1, mb: 2 }}>
          <TableBody>
            <TableRow>
              <TableCell>Download</TableCell>
              <TableCell>
                <Link href={download_url} download>Click to download</Link>
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>All Symbols</TableCell>
              <TableCell>
                <Link href={symbols_url} download>Click to download</Link>
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>BuildID</TableCell>
              <TableCell>{buildid}</TableCell>
            </TableRow>
            <TableRow>
              <TableCell>MD5</TableCell>
              <TableCell>{md5}</TableCell>
            </TableRow>
            {symbolRows}
          </TableBody>
        </Table>
      )}
    </Box>
  );
}

function App() {
  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState(null);
  const [lastQuery, setLastQuery] = useState(null);
  const [pageSize, setPageSize] = useState(DEFAULT_LIMIT);

  const onSearch = (data, offset = 0, limit = pageSize) => {
    setLastQuery(data);
    setLoading(true);
    (async () => {
      try {
        setResults(await api('/find', data, { limit, offset }));
      } finally {
        setLoading(false);
      }
    })();
  };

  const onPageSizeChange = (evt) => {
    const nextPageSize = Number(evt.target.value);
    setPageSize(nextPageSize);

    if (lastQuery !== null) {
      onSearch(lastQuery, 0, nextPageSize);
    }
  };

  const normalizedResults = Array.isArray(results)
    ? {
        results,
        total: results.length,
        offset: 0,
        limit: results.length,
        count: results.length,
        has_more: false,
      }
    : results;
  const displayedResults = normalizedResults?.results ?? [];
  const totalResults = normalizedResults?.total ?? 0;
  const currentOffset = normalizedResults?.offset ?? 0;
  const currentLimit = normalizedResults?.limit ?? DEFAULT_LIMIT;
  const currentCount = normalizedResults?.count ?? displayedResults.length;
  const startResult = currentCount > 0 ? currentOffset + 1 : 0;
  const endResult = currentCount > 0 ? Math.min(totalResults, currentOffset + currentCount) : 0;
  const canGoBack = currentOffset > 0;
  const canGoForward = normalizedResults?.has_more ?? false;

  return (
    <div className="App">
      <p>
        Powered by the{' '}
        <Link href="https://github.com/niklasb/libc-database/tree/master/searchengine">
          libc-database search API
        </Link>
      </p>

      <Grid container spacing={2}>
        <Grid item xs={12} md={6}>
          <h3>Search</h3>
          <SearchForm onSearch={onSearch} />
        </Grid>
        <Grid item xs={12} md={6}>
          <h3>Results</h3>
          {loading && <CircularProgress />}
          {results !== null && (
            <>
              <p>
                Showing {currentCount > 0 ? `${startResult}-${endResult}` : '0'} of {totalResults} results
              </p>
              {displayedResults.map((x) => <Result key={x.id} {...x} />)}
              <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} sx={{ mt: 2, alignItems: { xs: 'stretch', sm: 'center' } }}>
                <TextField
                  select
                  label="Page size"
                  value={pageSize}
                  onChange={onPageSizeChange}
                  sx={{ minWidth: 140 }}
                >
                  {PAGE_SIZE_OPTIONS.map((size) => (
                    <MenuItem key={size} value={size}>
                      {size}
                    </MenuItem>
                  ))}
                </TextField>
                <Button
                  type="button"
                  variant="outlined"
                  disabled={!canGoBack || loading || !lastQuery}
                  onClick={() => onSearch(lastQuery, Math.max(0, currentOffset - currentLimit))}
                >
                  Previous
                </Button>
                <Button
                  type="button"
                  variant="outlined"
                  disabled={!canGoForward || loading || !lastQuery}
                  onClick={() => onSearch(lastQuery, currentOffset + currentLimit)}
                >
                  Next
                </Button>
              </Stack>
            </>
          )}
        </Grid>
      </Grid>
    </div>
  );
}

export default App;